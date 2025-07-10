class BasicInfoCache {
  static String manufacturer = 'Loading...';
  static String deviceModel = 'Loading...';
  static String barCode = 'Loading...';
  static String productionDate = 'Loading...';
  static String version = 'Loading...';
  static bool isLoaded = false;
  
  static void clear() {
    manufacturer = 'Loading...';
    deviceModel = 'Loading...';
    barCode = 'Loading...';
    productionDate = 'Loading...';
    version = 'Loading...';
    isLoaded = false;
  }
}