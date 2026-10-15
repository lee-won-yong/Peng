package com.example.peng

import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val databaseQueue = Executors.newSingleThreadExecutor()
    private var database: SQLiteDatabase? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "peng/database")
            .setMethodCallHandler { call, result ->
                databaseQueue.execute {
                    try {
                        val path = getDatabasePath("peng.sqlite")
                        path.parentFile?.mkdirs()
                        val db = database ?: SQLiteDatabase.openOrCreateDatabase(path, null).also {
                            it.setForeignKeyConstraintsEnabled(true)
                            database = it
                        }
                        val value: Any? = when (call.method) {
                            "path" -> path.absolutePath
                            "batch" -> {
                                val statements = call.arguments as List<*>
                                db.beginTransaction()
                                try {
                                    statements.forEach { entry ->
                                        val statement = entry as Map<*, *>
                                        val args = (statement["args"] as? List<*>) ?: emptyList<Any>()
                                        db.execSQL(statement["sql"] as String, args.toTypedArray())
                                    }
                                    db.setTransactionSuccessful()
                                } finally {
                                    db.endTransaction()
                                }
                                null
                            }
                            "query" -> {
                                val statement = call.arguments as Map<*, *>
                                val args = (statement["args"] as? List<*>) ?: emptyList<Any>()
                                db.rawQuery(statement["sql"] as String, args.map { it.toString() }.toTypedArray()).use { cursor ->
                                    val rows = mutableListOf<Map<String, Any?>>()
                                    while (cursor.moveToNext()) {
                                        rows.add(cursor.columnNames.mapIndexed { index, name ->
                                            name to when (cursor.getType(index)) {
                                                Cursor.FIELD_TYPE_NULL -> null
                                                Cursor.FIELD_TYPE_INTEGER -> cursor.getLong(index)
                                                else -> cursor.getString(index)
                                            }
                                        }.toMap())
                                    }
                                    rows
                                }
                            }
                            else -> {
                                runOnUiThread { result.notImplemented() }
                                return@execute
                            }
                        }
                        runOnUiThread { result.success(value) }
                    } catch (error: Exception) {
                        runOnUiThread { result.error("sqlite", "학습 데이터 저장소 작업에 실패했어요.", null) }
                    }
                }
            }
    }

    override fun onDestroy() {
        databaseQueue.execute { database?.close(); database = null }
        databaseQueue.shutdown()
        super.onDestroy()
    }
}
