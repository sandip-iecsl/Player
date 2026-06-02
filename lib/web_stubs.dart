// Web stubs for mobile-only functionality

class Directory {
  final String path;
  Directory(this.path);
  
  Future<bool> exists() async => false;
  Future<Directory> create({bool recursive = false}) async => this;
  List<dynamic> listSync() => [];
}

class File {
  final String path;
  File(this.path);
  
  Future<bool> exists() async => false;
  Future<void> delete() async {}
}

Future<Directory?> getDownloadsDirectory() async => null;