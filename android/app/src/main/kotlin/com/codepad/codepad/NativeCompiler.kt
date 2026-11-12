package com.codepad.codepad

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.io.OutputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Phase 3：真实的 C 编译执行。
 *
 * 实现要点（每一步都对应一个 Android 限制）：
 *
 * 1. 编译器本体 tcc（Termux 移植的 aarch64 PIE）打包在 `jniLibs/arm64-v8a/libtcc.so`，
 *    APK 安装后位于 `nativeLibraryDir`，该目录下的文件带有可执行权限，
 *    不受「targetSdk ≥ 29 的应用数据目录不可 execve」限制。
 * 2. 编译与运行合并为 `tcc -run`：用户代码在 tcc 进程内即时编译到内存执行，
 *    因此不会产生「需要再次 exec 的 ELF 文件」，绕开同一个限制。
 * 3. bionic 头文件（来自 ndk-sysroot）与 tcc 的 libtcc1.a / crt 放在 assets，
 *    首次使用时解压到 filesDir/toolchain，通过 -B / -I 显式指给 tcc。
 *
 * 输出通过 MethodChannel 的 "onOutput" 回调实时回传 Dart 侧。
 */
class NativeCompiler(
    private val context: Context,
    private val channel: MethodChannel,
) : MethodChannel.MethodCallHandler {

    private val main = Handler(Looper.getMainLooper())
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()

    @Volatile
    private var running: Process? = null

    @Volatile
    private var stdin: OutputStream? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "probe" -> executor.execute {
                val payload = try {
                    probe()
                } catch (error: Exception) {
                    mapOf<String, Any?>("available" to false, "error" to error.toString())
                }
                main.post { result.success(payload) }
            }

            "run" -> {
                val sources = call.argument<List<String>>("sources")
                    ?: listOfNotNull(call.argument<String>("sourcePath"))
                if (sources.isEmpty()) {
                    main.post { result.error("bad_args", "sources 不能为空", null) }
                    return@onMethodCall
                }
                val extraArgs = call.argument<List<String>>("args") ?: emptyList()
        // 编译选项（-std=… / -O… / -Wall）由 Dart 侧按设置传入
        val compilerFlags = call.argument<List<String>>("flags") ?: emptyList()
                executor.execute {
                    val payload = try {
                        runProgram(sources, extraArgs, compilerFlags)
                    } catch (error: Exception) {
                        mapOf<String, Any?>(
                            "exitCode" to -1,
                            "error" to (error.message ?: error.toString()),
                        )
                    }
                    main.post { result.success(payload) }
                }
            }

            "writeStdin" -> {
                val text = call.argument<String>("text") ?: ""
                val ok = try {
                    stdin?.let { it.write(text.toByteArray()); it.flush(); true } ?: false
                } catch (error: IOException) {
                    false
                }
                main.post { result.success(ok) }
            }

            "closeStdin" -> {
                val ok = try {
                    stdin?.let { it.close(); true } ?: false
                } catch (error: IOException) {
                    false
                }
                stdin = null
                main.post { result.success(ok) }
            }

            "cancel" -> {
                val process = running
                running = null
                stdin = null
                process?.destroy()
                main.post { result.success(process != null) }
            }

            else -> main.post { result.notImplemented() }
        }
    }

    /** 检测内置工具链是否可用，返回给 Dart 侧的诊断信息。 */
    private fun probe(): Map<String, Any?> {
        val compiler = compilerPath()
            ?: return mapOf(
                "available" to false,
                "error" to "APK 内未找到编译器（nativeLibraryDir 下没有 libtcc.so）",
                "nativeLibraryDir" to context.applicationInfo.nativeLibraryDir,
            )

        val version = try {
            val process = ProcessBuilder(compiler.absolutePath, "-v")
                .redirectErrorStream(true)
                .start()
            val text = process.inputStream.bufferedReader().readText().trim()
            process.waitFor()
            text.lineSequence().firstOrNull { it.isNotBlank() } ?: text
        } catch (error: Exception) {
            return mapOf(
                "available" to false,
                "compilerPath" to compiler.absolutePath,
                "error" to "无法执行内置编译器：${error.message}",
            )
        }

        val toolchain = try {
            ensureToolchain()
        } catch (error: Exception) {
            return mapOf(
                "available" to false,
                "compilerPath" to compiler.absolutePath,
                "error" to "工具链解压失败：${error.message}",
            )
        }

        return mapOf(
            "available" to true,
            "compilerPath" to compiler.absolutePath,
            "toolchainDir" to toolchain.absolutePath,
            "version" to version,
            // 让自检报告自己证明「手机上的工具链到底解压出了什么」：
            // 每次远程排查最容易卡住的就是「究竟是老版本的 APK，还是解压不全」。
            "toolchainVersion" to TOOLCHAIN_VERSION,
            // 构建标记：自检报告会显示它，出问题时一眼确认「手机跑的是哪个包/哪条命令形状」。
            "buildTag" to BUILD_TAG,
            "checks" to linkedMapOf(
                "compat/sys/cdefs.h" to File(toolchain, "compat/sys/cdefs.h").isFile,
                "include/stdio.h" to File(toolchain, "include/stdio.h").isFile,
                "include/aarch64-linux-android" to File(toolchain, "include/aarch64-linux-android").isDirectory,
                "tcc/include/stdarg.h" to File(toolchain, "tcc/include/stdarg.h").isFile,
                "tcc/include/float.h" to File(toolchain, "tcc/include/float.h").isFile,
                "tcc/libtcc1.a" to File(toolchain, "tcc/libtcc1.a").isFile,
            ),
        )
    }

    private fun runProgram(
        sources: List<String>,
        extraArgs: List<String>,
        compilerFlags: List<String>,
    ): Map<String, Any?> {
        val compiler = compilerPath()
            ?: return mapOf("exitCode" to -1, "error" to "内置编译器缺失")
        val toolchain = ensureToolchain()
        val tccLib = File(toolchain, "tcc")
        val include = File(toolchain, "include")

        val command = mutableListOf(
            compiler.absolutePath,
            // -B 只声明「tcc 私有目录」（crt / 头文件默认位置）。
            // 注意：它【不】参与 libtcc1.a 的库搜索 —— 0.3.8 的真机报错
            // "tcc: error: libtcc1.a not found" 就是只给了 -B 造成的。
            "-B${tccLib.absolutePath}",
            // -L 才是库搜索路径：libtcc1.a 必须靠它找到（真机 = files/toolchain/tcc/libtcc1.a）。
            // 在开发机上把编译器旁边的 lib/ 与 include/ 全部移走后验证过：
            // 只有 -B 时 → library not found + undefined symbol '_runmain'；
            // 补上 -L 后 → 正常输出结果。
            "-L${tccLib.absolutePath}",
            // compat 必须排第一：它提供一份 tcc 友好的 sys/cdefs.h，
            // 把 _Nonnull / __RENAME(__asm__ 别名) / __attribute__((__availability__))
            // / __has_include 这些 clang 专有词汇抹平。否则 include <stdio.h> 必炸。
            "-I${File(toolchain, "compat").absolutePath}",
            "-I${include.absolutePath}",
            "-I${File(include, "aarch64-linux-android").absolutePath}",
            // 编译器自带的头（stdarg.h / varargs.h / stdalign.h / stdnoreturn.h / float.h …）
            // 必须显式给出：tcc 只会在「自己所在的目录」旁边找 include/，而真机上它是
            // APK 的 lib/arm64/libtcc.so，旁边没有 include/ —— 于是 bionic 的 stdio.h 里
            // 那句 #include <stdarg.h> 直接 "include file 'stdarg.h' not found"（真机日志）。
            // 少了这一条，所有探针都会卡在 stdio.h 第 46 行。
            "-I${File(tccLib, "include").absolutePath}",
            // 兜底：即使 compat 没生效，这两个宏也能让部分路径通过
            "-D__ANDROID_MIN_SDK_VERSION__=$ANDROID_MIN_SDK",
            "-D__ANDROID_API__=$ANDROID_MIN_SDK",
        )
        // 编译选项放在源文件之前：tcc 把「-run 之后」当程序参数，所以这些必须在前面
        command.addAll(compilerFlags)
        // 关键：-run 必须放在所有源文件之后。
        // tcc 的规则是「-run 之后的一切都当作被运行程序的参数」，
        // 所以写成 `-run a.c b.c` 时 b.c 根本不会被编译（只当一个参数传给 a.out），
        // 多文件立刻变成 undefined symbol。正确写法是 `tcc a.c b.c -run`。
        command.addAll(sources)
        command.add("-run")
        command.addAll(extraArgs)

        emit("info", "$ ${command.joinToString(" ")}")

        val startedAt = System.currentTimeMillis()
        val process = try {
            ProcessBuilder(command).directory(File(sources.first()).parentFile).start()
        } catch (error: IOException) {
            return mapOf("exitCode" to -1, "error" to "启动编译器失败：${error.message}")
        }

        running = process
        stdin = process.outputStream

        val stdoutReader = Thread {
            process.inputStream.bufferedReader().forEachLine { line -> emit("stdout", line) }
        }
        val stderrReader = Thread {
            process.errorStream.bufferedReader().forEachLine { line -> emit("stderr", line) }
        }
        stdoutReader.start()
        stderrReader.start()

        val exitCode = process.waitFor()
        stdoutReader.join()
        stderrReader.join()
        running = null
        stdin = null

        return mapOf(
            "exitCode" to exitCode,
            "durationMs" to (System.currentTimeMillis() - startedAt),
        )
    }

    private fun emit(stream: String, text: String) {
        main.post {
            channel.invokeMethod(
                "onOutput",
                mapOf("stream" to stream, "text" to text),
            )
        }
    }

    private fun compilerPath(): File? {
        val dir = File(context.applicationInfo.nativeLibraryDir)
        val candidate = File(dir, "libtcc.so")
        if (!candidate.isFile) {
            return null
        }
        // 解压后通常已带执行位，这里兜底一次
        if (!candidate.canExecute()) {
            candidate.setExecutable(true)
        }
        return candidate
    }

    /** 把 assets/toolchain 解压到 filesDir，返回根目录。 */
    private fun ensureToolchain(): File {
        val root = File(context.filesDir, "toolchain")
        val marker = File(root, "VERSION")
        // 缓存是否可用：不光看标记，还要抽查「每一条 -I 目录里都必须有的文件」。
        // 0.3.7 的真机故障就是 tcc 自带头缺失 —— 只查 include/stdio.h 发现不了，
        // 这里把 compat 垫片和 tcc/include 的关键文件也纳入校验，缺了就自动重新解压。
        val cacheOk = marker.isFile &&
            marker.readText().trim() == TOOLCHAIN_VERSION &&
            File(root, "tcc/libtcc1.a").isFile &&
            File(root, "include/stdio.h").isFile &&
            File(root, "include/aarch64-linux-android").isDirectory &&
            File(root, "compat/sys/cdefs.h").isFile &&
            File(root, "tcc/include/stdarg.h").isFile &&
            File(root, "tcc/include/float.h").isFile
        if (cacheOk) {
            return root
        }

        root.deleteRecursively()
        root.mkdirs()
        copyAsset("toolchain", root)
        marker.writeText(TOOLCHAIN_VERSION)
        return root
    }

    private fun copyAsset(assetPath: String, target: File) {
        val children = context.assets.list(assetPath) ?: emptyArray()
        if (children.isEmpty()) {
            target.parentFile?.mkdirs()
            try {
                context.assets.open(assetPath).use { input ->
                    target.outputStream().use { output -> input.copyTo(output) }
                }
            } catch (error: IOException) {
                // assets.list 对空目录也会返回空数组，这里容错跳过
                target.mkdirs()
            }
            return
        }
        target.mkdirs()
        for (child in children) {
            copyAsset("$assetPath/$child", File(target, child))
        }
    }

    private companion object {
        // 工具链内容变了就改这里：APP 首次运行会把 assets/toolchain 解压到 filesDir，
        // VERSION 不匹配会重新解压，否则会一直用旧的（0.3.2 的缺头文件问题就靠它刷新）。
        const val TOOLCHAIN_VERSION = "tcc-0.9.27-p20230415-android-7"

        /** 命令行形状变了就改这里：会出现在自检报告首屏，用来区分构建。 */
        const val BUILD_TAG = "1.0.0-c"

        /** 与 build.gradle.kts 的 minSdk 一致；bionic 头文件需要这个宏。 */
        const val ANDROID_MIN_SDK = 24
    }
}
