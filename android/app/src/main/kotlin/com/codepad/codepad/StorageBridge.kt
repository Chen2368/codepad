package com.codepad.codepad

import android.app.Activity
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/**
 * 「存储与更新」相关的原生能力：
 *  · 把工程目录打包导出到系统「下载」（MediaStore，Android 10+ 免存储权限）
 *  · 打开系统的「下载」界面
 *  · 让用户从本地挑一个 APK 交给系统安装器（SAF，不需要 FileProvider）
 *
 * 之所以不自己拼 file:// 去分享：API 24 起会抛 FileUriExposedException，
 * 而 SAF 返回的 content:// 带临时读权限，安装器能直接读。
 */
class StorageBridge(
    private val activity: Activity,
    private val channel: MethodChannel,
) : MethodChannel.MethodCallHandler {

    private var pendingResult: MethodChannel.Result? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "exportZip" -> {
                val source = call.argument<String>("sourceDir")
                val name = call.argument<String>("name") ?: "projects"
                if (source == null) {
                    result.error("no_source", "缺少工程目录", null)
                    return
                }
                try {
                    result.success(exportZip(File(source), name))
                } catch (error: Exception) {
                    Log.e(TAG, "导出失败", error)
                    result.error("export_failed", error.message ?: error.toString(), null)
                }
            }

            "openDownloads" -> {
                try {
                    val intent = Intent(android.app.DownloadManager.ACTION_VIEW_DOWNLOADS)
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    activity.startActivity(intent)
                    result.success(true)
                } catch (error: Exception) {
                    result.error("no_downloads_ui", error.message ?: error.toString(), null)
                }
            }

            "openUrl" -> {
                val url = call.argument<String>("url")
                if (url == null) {
                    result.error("no_url", "缺少 url", null)
                    return
                }
                try {
                    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    activity.startActivity(intent)
                    result.success(true)
                } catch (error: Exception) {
                    result.error("no_browser", error.message ?: error.toString(), null)
                }
            }

            "pickApk" -> {
                if (pendingResult != null) {
                    result.error("busy", "已经有一个选择器在等待结果", null)
                    return
                }
                pendingResult = result
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "application/vnd.android.package-archive"
                }
                try {
                    activity.startActivityForResult(intent, REQUEST_PICK_APK)
                } catch (error: Exception) {
                    pendingResult = null
                    result.error("no_file_picker", error.message ?: error.toString(), null)
                }
            }

            "installFromUri" -> {
                val text = call.argument<String>("uri")
                if (text == null) {
                    result.error("no_uri", "缺少 uri", null)
                    return
                }
                try {
                    installPackage(Uri.parse(text))
                    result.success(true)
                } catch (error: Exception) {
                    result.error("install_failed", error.message ?: error.toString(), null)
                }
            }

            else -> result.notImplemented()
        }
    }

    /** 供 MainActivity 转发 onActivityResult。 */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_PICK_APK) {
            return false
        }
        val pending = pendingResult
        pendingResult = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            pending?.success(mapOf("cancelled" to true))
            return true
        }
        val uri = data.data!!
        return try {
            // 交给系统安装器；安装器自己能读这个 content://（我们带了读权限）
            installPackage(uri)
            pending?.success(mapOf("cancelled" to false, "uri" to uri.toString()))
            true
        } catch (error: Exception) {
            pending?.error("install_failed", error.message ?: error.toString(), null)
            true
        }
    }

    private fun installPackage(uri: Uri) {
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        activity.startActivity(intent)
    }

    /**
     * 把 [source] 整个目录打成 zip 写进系统「下载」目录下的 CodePad 文件夹。
     *
     * Android 10+ 走 MediaStore，不需要 WRITE_EXTERNAL_STORAGE；
     * 老系统退回到应用自己的外部目录（无需权限，但卸载会被清掉）。
     */
    private fun exportZip(source: File, name: String): Map<String, Any?> {
        if (!source.exists()) {
            throw IllegalStateException("工程目录不存在：${source.absolutePath}")
        }
        val stamp = SimpleDateFormat("yyyyMMdd-HHmm", Locale.US).format(Date())
        val fileName = "$name-$stamp.zip"
        // 计数放在数组里，lambda 才能改
        val counter = intArrayOf(0)
        val writeCounted: (java.io.OutputStream) -> Unit = { output ->
            ZipOutputStream(output).use { zip ->
                source.walkTopDown().forEach { file ->
                    if (file.isFile) {
                        counter[0]++
                        val relative = file.absolutePath
                            .removePrefix(source.absolutePath)
                            .trimStart(File.separatorChar)
                        zip.putNextEntry(ZipEntry("$name/$relative"))
                        file.inputStream().use { input -> input.copyTo(zip) }
                        zip.closeEntry()
                    }
                }
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                put(MediaStore.Downloads.MIME_TYPE, "application/zip")
                put(MediaStore.Downloads.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/CodePad")
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val resolver = activity.contentResolver
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("无法在「下载」里创建文件")
            resolver.openOutputStream(uri)?.use { writeCounted(it) }
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            return mapOf(
                "path" to "Download/CodePad/$fileName",
                "uri" to uri.toString(),
                "fileCount" to counter[0],
            )
        }

        val dir = File(
            activity.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS),
            "CodePad",
        )
        dir.mkdirs()
        val target = File(dir, fileName)
        FileOutputStream(target).use { writeCounted(it) }
        return mapOf(
            "path" to target.absolutePath,
            "uri" to Uri.fromFile(target).toString(),
            "fileCount" to counter[0],
        )
    }

    private companion object {
        const val TAG = "CodePadStorage"
        const val REQUEST_PICK_APK = 4711
    }
}
