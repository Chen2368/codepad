package com.codepad.codepad

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var storageBridge: StorageBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val compilerChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "codepad/compiler")
        compilerChannel.setMethodCallHandler(NativeCompiler(applicationContext, compilerChannel))

        val storageChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "codepad/storage")
        val bridge = StorageBridge(this, storageChannel)
        storageChannel.setMethodCallHandler(bridge)
        storageBridge = bridge
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
