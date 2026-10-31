package sk.zdenoiva.raritio

import android.Manifest
import android.content.ContentResolver
import android.content.ContentUris
import android.content.ContentValues
import android.content.pm.PackageManager
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.widget.Toast
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
    private val backupChannel = "sk.zdenoiva.raritio/backup"
    private val securityChannel = "sk.zdenoiva.raritio/security"
    private val storagePermissionRequest = 1002

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            backupChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveBackupToDownloads" -> {
                    val fileName = call.argument<String>("fileName")
                    val content = call.argument<String>("content")
                    val maxBackups = call.argument<Int>("maxBackups") ?: 5

                    if (fileName.isNullOrBlank() || content == null) {
                        result.error("ARG_ERROR", "fileName and content are required", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val path = saveBackupToDownloads(fileName, content, maxBackups)
                        result.success(path)
                    } catch (e: Exception) {
                        result.error("BACKUP_ERROR", e.message, null)
                    }
                }

                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            securityChannel,
        ).setMethodCallHandler { call, result ->
            if (call.method == "getApkSignerSha256") {
                val path = call.argument<String>("path")
                if (path.isNullOrBlank()) {
                    result.error("ARG_ERROR", "path is required", null)
                    return@setMethodCallHandler
                }
                try {
                    result.success(apkSignerSha256(path))
                } catch (e: Exception) {
                    result.error("SIGNATURE_ERROR", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun apkSignerSha256(path: String): String {
        val packageManager = packageManager
        val archiveInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageManager.getPackageArchiveInfo(
                path,
                PackageManager.GET_SIGNING_CERTIFICATES,
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.getPackageArchiveInfo(
                path,
                PackageManager.GET_SIGNATURES,
            )
        } ?: throw IllegalStateException("APK sa nepodarilo prečítať.")

        val signatureBytes = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            archiveInfo.signingInfo?.apkContentsSigners?.firstOrNull()?.toByteArray()
        } else {
            @Suppress("DEPRECATION")
            archiveInfo.signatures?.firstOrNull()?.toByteArray()
        } ?: throw IllegalStateException("APK nemá podpis.")

        return MessageDigest.getInstance("SHA-256")
            .digest(signatureBytes)
            .joinToString("") { "%02x".format(it) }
    }

    private fun saveBackupToDownloads(
        fileName: String,
        content: String,
        maxBackups: Int,
    ): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = contentResolver
            val relativePath = "${Environment.DIRECTORY_DOWNLOADS}/Raritio"
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(MediaStore.MediaColumns.MIME_TYPE, "application/json")
                put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }

            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("Nepodarilo sa vytvoriť súbor v Downloads.")
            try {
                resolver.openOutputStream(uri)?.use { output ->
                    output.write(content.toByteArray(Charsets.UTF_8))
                } ?: throw IllegalStateException("Nepodarilo sa otvoriť súbor v Downloads.")

                val done = ContentValues().apply {
                    put(MediaStore.MediaColumns.IS_PENDING, 0)
                }
                resolver.update(uri, done, null, null)
            } catch (e: Exception) {
                resolver.delete(uri, null, null)
                throw e
            }

            pruneMediaStoreBackups(resolver, relativePath, maxBackups)
            return "Download/Raritio/$fileName"
        }

        if (ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.WRITE_EXTERNAL_STORAGE,
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                storagePermissionRequest,
            )
            Toast.makeText(
                this,
                "Povoľ ukladanie do Downloads a skús zálohu znova.",
                Toast.LENGTH_LONG,
            ).show()
            throw SecurityException("Chýba povolenie na zápis do Downloads.")
        }

        val base = Environment.getExternalStoragePublicDirectory(
            Environment.DIRECTORY_DOWNLOADS,
        )
        val dir = File(base, "Raritio")
        if (!dir.exists() && !dir.mkdirs()) {
            throw IllegalStateException("Nepodarilo sa vytvoriť priečinok Downloads/Raritio.")
        }
        val file = File(dir, fileName)
        file.writeText(content, Charsets.UTF_8)
        pruneFileBackups(dir, maxBackups)
        return "Download/Raritio/$fileName"
    }

    private fun pruneMediaStoreBackups(
        resolver: ContentResolver,
        relativePath: String,
        maxBackups: Int,
    ) {
        val projection = arrayOf(MediaStore.MediaColumns._ID)
        val selection =
            "${MediaStore.MediaColumns.RELATIVE_PATH} LIKE ? AND " +
                "${MediaStore.MediaColumns.DISPLAY_NAME} LIKE ?"
        val args = arrayOf("$relativePath/%", "raritio-zaloha-%")
        val ids = mutableListOf<Long>()

        resolver.query(
            MediaStore.Downloads.EXTERNAL_CONTENT_URI,
            projection,
            selection,
            args,
            "${MediaStore.MediaColumns.DATE_ADDED} ASC",
        )?.use { cursor ->
            val idIndex = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
            while (cursor.moveToNext()) {
                ids.add(cursor.getLong(idIndex))
            }
        }

        while (ids.size > maxBackups) {
            val id = ids.removeAt(0)
            resolver.delete(
                ContentUris.withAppendedId(
                    MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                    id,
                ),
                null,
                null,
            )
        }
    }

    private fun pruneFileBackups(dir: File, maxBackups: Int) {
        val files = dir.listFiles { file ->
            file.isFile &&
                file.name.startsWith("raritio-zaloha-") &&
                (file.name.endsWith(".raritio") || file.name.endsWith(".json"))
        }?.sortedBy { it.name }?.toMutableList() ?: return

        while (files.size > maxBackups) {
            files.removeAt(0).delete()
        }
    }
}
