package dev.steenbakker.mobile_scanner.objects

// PreppSuite patch: ML Kit's format constants written out, so this enum
// no longer needs ML Kit. The numbers are the plugin's on the Dart side.
enum class BarcodeFormats(val intValue: Int) {
    UNKNOWN(-1),
    ALL_FORMATS(0),
    CODE_128(1),
    CODE_39(2),
    CODE_93(4),
    CODABAR(8),
    DATA_MATRIX(16),
    EAN_13(32),
    EAN_8(64),
    ITF(128),
    QR_CODE(256),
    UPC_A(512),
    UPC_E(1024),
    PDF417(2048),
    AZTEC(4096);

    companion object {
        fun fromRawValue(rawValue: Int): BarcodeFormats {
            return when(rawValue) {
                -1 -> UNKNOWN
                0 -> ALL_FORMATS
                1 -> CODE_128
                2 -> CODE_39
                4 -> CODE_93
                8 -> CODABAR
                16 -> DATA_MATRIX
                32 -> EAN_13
                64 -> EAN_8
                126, 127, 128 -> ITF
                256 -> QR_CODE
                512 -> UPC_A
                1024 -> UPC_E
                2048 -> PDF417
                4096 -> AZTEC
                else -> UNKNOWN
            }
        }
    }
}