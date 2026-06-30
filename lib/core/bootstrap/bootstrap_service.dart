import '../utils/logger.dart';

class BootstrapService {
  final List<String> seedNodes = [
    "node-1",
    "node-2",
    "node-3",
  ];

  List<String> getSeeds() {
    Logger.info("Loading seed nodes");
    return seedNodes;
  }
}