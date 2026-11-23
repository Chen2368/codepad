package com.codepad.codepad

import android.content.Intent
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class MainActivity : FlutterActivity() {

    private var storageBridge: StorageBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        installCrashHandler()

        val compilerChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "codepad/compiler")
        compilerChannel.setMethodCallHandler(NativeCompiler(applicationContext, compilerChannel))

        val storageChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "codepad/storage")
        val bridge = StorageBridge(this, storageChannel)
        storageChannel.setMethodCallHandler(bridge)
        storageBridge = bridge
    }

    /**
     * 未捕获的 Java/Kotlin 异常写一份到 filesDir/diag/crash-native.log。
     *
     * 注意：**它抓不到 JIT 代码里的段错误**（tcc 跑飞的 C 程序直接给进程发 SIGSEGV），
     * 那种情况靠 darwin/ART 的默认处理直接把进程干掉，只能靠 Dart 侧写的「会话标记」
     * 在下次启动时判断「上次没正常收尾」。
     */
    private fun installCrashHandler() {
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            try {
                val dir = File(filesDir, "diag")
                dir.mkdirs()
                val stamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US)
                    .format(Date())
                val writer = StringWriter()
                throwable.printStackTrace(PrintWriter(writer))
                File(dir, "crash-native.log").appendText(
                    "\n=== $stamp  thread=${thread.name} ===\n" + writer.toString(),
                )
            } catch (error: Throwable) {
                Log.e("CodePadCrash", "写崩溃日志失败", error)
            }
            previous?.uncaughtException(thread, throwable)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        // 先交给桥接处理（选择本地 APK）；不是它的请求再走默认流程
        if (storageBridge?.onActivityResult(requestCode, resultCode, data) == true) {
            return
        }
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
    }
}