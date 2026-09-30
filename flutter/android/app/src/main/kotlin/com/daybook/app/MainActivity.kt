package com.daybook.app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.print.PrintAttributes
import android.print.PrintDocumentAdapter
import android.print.PrintManager
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.io.ByteArrayOutputStream
import java.nio.charset.StandardCharsets

class MainActivity : FlutterActivity() {
    private var pendingOpen: MethodChannel.Result? = null
    private var pendingSave: MethodChannel.Result? = null
    private var pendingBackupContents: String? = null
    private var reportWebView: WebView? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getBootstrapData" -> result.success(bootstrapData())
                    "getThemeStyle" -> result.success(
                        getSharedPreferences(UI_SETTINGS_NAME, Context.MODE_PRIVATE)
                            .getString(THEME_STYLE_KEY, "classic")
                    )
                    "setThemeStyle" -> setThemeStyle(call.argument("style"), result)
                    "markDataImportComplete" -> {
                        getSharedPreferences(STORAGE_NAME, Context.MODE_PRIVATE)
                            .edit()
                            .putBoolean(DATA_IMPORT_COMPLETE_KEY, true)
                            .apply()
                        result.success(null)
                    }
                    "pickBackup" -> pickBackup(result)
                    "saveBackup" -> saveBackup(call.argument("filename"), call.argument("contents"), result)
                    "printReport" -> printReport(call.argument("title"), call.argument("html"), result)
                    "openExternalUrl" -> openExternalUrl(call.argument("url"), result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun bootstrapData(): Map<String, String?> {
        val preferences = getSharedPreferences(STORAGE_NAME, Context.MODE_PRIVATE)
        val primary = preferences.getString(DATA_KEY, null)
        val recovery = preferences.getString(RECOVERY_KEY, null)
        val original = preferences.getString(ORIGINAL_KEY, null)
        return mapOf(
            "dataDirectory" to filesDir.absolutePath,
            "legacyJson" to (primary ?: recovery ?: original),
            "legacyPrimary" to primary,
            "legacyRecovery" to recovery,
            "legacyOriginal" to original,
        )
    }

    private fun setThemeStyle(style: String?, result: MethodChannel.Result) {
        if (style !in setOf("classic", "ocean", "forest")) {
            result.error("invalidThemeStyle", "The theme style is not supported.", null)
            return
        }
        getSharedPreferences(UI_SETTINGS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(THEME_STYLE_KEY, style)
            .apply()
        result.success(null)
    }

    private fun pickBackup(result: MethodChannel.Result) {
        if (pendingOpen != null) {
            result.error("backupBusy", "A backup is already being opened.", null)
            return
        }
        pendingOpen = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/json"
        }
        try {
            startActivityForResult(intent, OPEN_BACKUP_REQUEST)
        } catch (_: Exception) {
            pendingOpen = null
            result.error("pickerUnavailable", "The document picker is unavailable.", null)
        }
    }

    private fun saveBackup(filename: String?, contents: String?, result: MethodChannel.Result) {
        if (pendingSave != null || pendingBackupContents != null) {
            result.error("backupBusy", "A backup is already being saved.", null)
            return
        }
        if (filename.isNullOrBlank() || contents == null || contents.toByteArray(StandardCharsets.UTF_8).size > MAX_BACKUP_BYTES) {
            result.error("backupFailed", "The backup is invalid or too large.", null)
            return
        }
        pendingBackupContents = contents
        pendingSave = result
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/json"
            putExtra(Intent.EXTRA_TITLE, filename)
        }
        try {
            startActivityForResult(intent, SAVE_BACKUP_REQUEST)
        } catch (_: Exception) {
            pendingBackupContents = null
            pendingSave = null
            result.error("pickerUnavailable", "The document picker is unavailable.", null)
        }
    }

    private fun openExternalUrl(value: String?, result: MethodChannel.Result) {
        val uri = value?.let(Uri::parse)
        if (uri == null || uri.scheme != "https") {
            result.error("invalidUrl", "Only secure web links can be opened.", null)
            return
        }
        try {
            startActivity(Intent(Intent.ACTION_VIEW, uri))
            result.success(null)
        } catch (_: Exception) {
            result.error("linkUnavailable", "The link could not be opened.", null)
        }
    }

    private fun printReport(title: String?, html: String?, result: MethodChannel.Result) {
        if (reportWebView != null) {
            result.error("printBusy", "A report is already being prepared.", null)
            return
        }
        if (title.isNullOrBlank() || html == null || html.length > MAX_REPORT_LENGTH) {
            result.error("printFailed", "The report is invalid or too large.", null)
            return
        }
        val view = WebView(this)
        reportWebView = view
        view.settings.javaScriptEnabled = false
        view.settings.allowFileAccess = false
        view.settings.allowContentAccess = false
        view.settings.blockNetworkLoads = true
        view.webViewClient = object : WebViewClient() {
            private var started = false

            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean = true

            override fun onPageFinished(view: WebView, url: String) {
                if (started || reportWebView !== view || isFinishing) return
                started = true
                try {
                    val manager = getSystemService(Context.PRINT_SERVICE) as? PrintManager
                        ?: throw IllegalStateException("Print service unavailable")
                    val delegate = view.createPrintDocumentAdapter(title)
                    val adapter = object : PrintDocumentAdapter() {
                        override fun onStart() = delegate.onStart()

                        override fun onLayout(
                            oldAttributes: PrintAttributes?,
                            newAttributes: PrintAttributes,
                            cancellationSignal: android.os.CancellationSignal,
                            callback: LayoutResultCallback,
                            extras: Bundle?,
                        ) = delegate.onLayout(oldAttributes, newAttributes, cancellationSignal, callback, extras)

                        override fun onWrite(
                            pages: Array<out android.print.PageRange>,
                            destination: android.os.ParcelFileDescriptor,
                            cancellationSignal: android.os.CancellationSignal,
                            callback: WriteResultCallback,
                        ) = delegate.onWrite(pages, destination, cancellationSignal, callback)

                        override fun onFinish() {
                            delegate.onFinish()
                            releaseReport()
                        }
                    }
                    manager.print(
                        title,
                        adapter,
                        PrintAttributes.Builder()
                            .setMediaSize(PrintAttributes.MediaSize.ISO_A4)
                            .setColorMode(PrintAttributes.COLOR_MODE_COLOR)
                            .build(),
                    )
                    result.success(null)
                } catch (_: RuntimeException) {
                    releaseReport()
                    result.error("printFailed", "The report could not be printed.", null)
                }
            }
        }
        view.loadDataWithBaseURL(null, html, "text/html", "UTF-8", null)
    }

    private fun releaseReport() {
        reportWebView?.destroy()
        reportWebView = null
    }

    @Deprecated("Deprecated in Android")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == OPEN_BACKUP_REQUEST) {
            readBackup(resultCode, data)
            return
        }
        if (requestCode == SAVE_BACKUP_REQUEST) {
            writeBackup(resultCode, data)
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun readBackup(resultCode: Int, data: Intent?) {
        val result = pendingOpen
        pendingOpen = null
        val uri = if (resultCode == RESULT_OK) data?.data else null
        if (result == null) return
        if (uri == null) {
            result.success(null)
            return
        }
        try {
            val contents = contentResolver.openInputStream(uri)?.use { input ->
                val bytes = ByteArrayOutputStream()
                val buffer = ByteArray(8192)
                var total = 0
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    total += count
                    if (total > MAX_BACKUP_BYTES) throw IOException("Backup exceeds the supported size.")
                    bytes.write(buffer, 0, count)
                }
                String(bytes.toByteArray(), StandardCharsets.UTF_8)
            } ?: throw IOException("The selected backup could not be read.")
            result.success(contents)
        } catch (_: Exception) {
            result.error("backupFailed", "The selected backup could not be read.", null)
        }
    }

    private fun writeBackup(resultCode: Int, data: Intent?) {
        val result = pendingSave
        val contents = pendingBackupContents
        pendingSave = null
        pendingBackupContents = null
        val uri = if (resultCode == RESULT_OK) data?.data else null
        if (result == null) return
        if (uri == null) {
            result.success(false)
            return
        }
        try {
            contentResolver.openOutputStream(uri, "wt")?.use { output ->
                output.write(contents?.toByteArray(StandardCharsets.UTF_8) ?: throw IOException("Backup was interrupted."))
                output.flush()
            } ?: throw IOException("The selected destination could not be opened.")
            result.success(true)
        } catch (_: Exception) {
            result.error("backupFailed", "The backup could not be written.", null)
        }
    }

    override fun onDestroy() {
        releaseReport()
        pendingOpen?.error("backupInterrupted", "Opening the backup was interrupted.", null)
        pendingSave?.error("backupInterrupted", "Saving the backup was interrupted.", null)
        pendingOpen = null
        pendingSave = null
        pendingBackupContents = null
        super.onDestroy()
    }

    private companion object {
        const val CHANNEL = "com.daybook.app/legacy"
        const val STORAGE_NAME = "daybook_storage"
        const val UI_SETTINGS_NAME = "pouch_ui_settings"
        const val THEME_STYLE_KEY = "theme_style"
        const val DATA_KEY = "daybook.budget.v1"
        const val RECOVERY_KEY = "daybook.budget.v1.recovery"
        const val ORIGINAL_KEY = "daybook.budget.v1.original"
        const val DATA_IMPORT_COMPLETE_KEY = "pouch.rust.data_import_complete"
        const val OPEN_BACKUP_REQUEST = 49101
        const val SAVE_BACKUP_REQUEST = 49102
        const val MAX_BACKUP_BYTES = 5_000_000
        const val MAX_REPORT_LENGTH = 10_000_000
    }
}
