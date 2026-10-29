import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  DatabaseHelper._internal();

  factory DatabaseHelper.instance() => _instance;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final Directory documentsDirectory = await getApplicationDocumentsDirectory();
    final String path = join(documentsDirectory.path, 'raritio.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE cards (
            id TEXT PRIMARY KEY,
            name TEXT,
            set TEXT,
            type TEXT,
            imageUri TEXT,
            game TEXT,
            currentPrice REAL,
            lastUpdated TEXT,
            metadata TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE binders (
            id TEXT PRIMARY KEY,
            name TEXT,
            description TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE binder_cards (
            binderId TEXT,
            cardId TEXT,
            FOREIGN KEY(binderId) REFERENCES binders(id) ON DELETE CASCADE,
            FOREIGN KEY(cardId) REFERENCES cards(id) ON DELETE CASCADE
          )
        ''');
      },
    );
  }

  Future<int> insertCard(Map<String, dynamic> card) async {
    final db = await database;
    return await db.insert('cards', {
      'id': card['id'],
      'name': card['name'],
      'set': card['set'],
      'type': card['type'],
      'imageUri': card['imageUri'],
      'game': card['game'],
      'currentPrice': card['currentPrice'],
      'lastUpdated': card['lastUpdated'],
      'metadata': jsonEncode(card['metadata']),
    });
  }

  Future<List<Map<String, dynamic>>> getBinders() async {
    final db = await database;
    return await db.query('binders');
  }

  Future<int> insertBinder(Map<String, dynamic> binder) async {
    final db = await database;
    return await db.insert('binders', {
      'id': binder['id'],
      'name': binder['name'],
      'description': binder['description'],
    });
  }

  Future<void> linkCardToBinder(String binderId, String cardId) async {
    final db = await database;
    await db.insert('binder_cards', {
      'binderId': binderId,
      'cardId': cardId,
    });
  }
}

