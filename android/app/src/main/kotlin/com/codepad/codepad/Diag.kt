package com.codepad.codepad

import android.content.Context
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 诊断日志的唯一入口（Dart 通道、Activity 生命周期都走这里）。
 *
 * 为什么要统一：闪退取证最怕「多处各写一份、格式不一致」。
 * 这里约定行格式 `MM-dd HH:mm:ss.SSS  kind|detail`，Dart 侧
 * `parseSessionLog` 按同一格式解析。
 */
object Diag {

    private const val MAX_BYTES = 256 * 1024

    fun dir(context: Context): File {
        val dir = File(context.filesDir, "diag")
        if (!dir.exists()) {
            dir.mkdirs()
        }
        return dir
    }

    /** 追加一行；超过 256 KB 滚动一次（session.log → session.1.log）。 */
    fun append(context: Context, kind: String, detail: String = "") {
        try {
            val target = File(dir(context), "session.log")
            if (target.exists() && target.length() > MAX_BYTES) {
                val old = File(dir(context), "session.1.log")
                if (old.exists()) {
                    old.delete()
                }
                target.renameTo(old)
            }
            val stamp = SimpleDateFormat("MM-dd HH:mm:ss.SSS", Locale.US).format(Date())
            target.appendText("$stamp  $kind|$detail\n")
        } catch (error: Throwable) {
            // 诊断失败绝不能影响主流程
        }
    }

    /** 读回日志：原生崩溃 + 当前会话（尾部 200 行）+ 上一段会话（尾部 120 行）。 */
    fun read(context: Context): String {
        val builder = StringBuilder()
        val crash = File(dir(context), "crash-native.log")
        if (crash.exists()) {
            builder.append("==== 原生未捕获异常 ====\n")
            builder.append(crash.readText())
            builder.append("\n")
        }
        val session = File(dir(context), "session.log")
        if (session.exists()) {
            builder.append("==== 会话记录（最近 200 行）====\n")
            builder.append(session.readLines().takeLast(200).joinToString("\n"))
            builder.append("\n")
        }
        val previous = File(dir(context), "session.1.log")
        if (previous.exists()) {
            builder.append("==== 上一段会话（末尾 120 行）====\n")
            builder.append(previous.readLines().takeLast(120).joinToString("\n"))
            builder.append("\n")
        }
        return if (builder.isEmpty()) "（还没有日志）\n" else builder.toString()
    }

    /**
     * 内存快照。判断「闪退是不是 OOM」全靠它：
     * 如果运行前后 Java 堆接近 max，或 native 堆几百 MB，基本就是被系统当内存杀手干掉的。
     */
    fun memInfo(): Map<String, Any?> {
        val runtime = Runtime.getRuntime()
        val usedMb = (runtime.totalMemory() - runtime.freeMemory()) / (1024 * 1024)
        val maxMb = runtime.maxMemory() / (1024 * 1024)
        val nativeMb = android.os.Debug.getNativeHeapAllocatedSize() / (1024 * 1024)
        return mapOf(
            "javaUsedMb" to usedMb,
            "javaMaxMb" to maxMb,
            "nativeMb" to nativeMb,
        )
    }

    /** 一行可读的内存摘要，用于写进 session.log。 */
    fun memSummary(): String {
        val info = memInfo()
        return "java=${info["javaUsedMb"]}/${info["javaMaxMb"]}MB native=${info["nativeMb"]}MB"
    }
}