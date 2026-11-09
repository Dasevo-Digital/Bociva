package dev.steenbakker.mobile_scanner

import android.graphics.Bitmap
import android.graphics.Point
import androidx.camera.core.ImageProxy
import dev.steenbakker.mobile_scanner.objects.BarcodeFormats
import zxingcpp.BarcodeReader

/**
 * PreppSuite patch: reads barcodes with zxing-cpp instead of ML Kit.
 *
 * ML Kit sends usage figures to Google on every use -- device, app,
 * an installation identifier, timings and events -- and its terms offer
 * no way to turn that off. zxing-cpp runs in the app and sends nothing.
 * See third_party/LIESMICH.md.
 *
 * Everything the Dart side reads stays as it was: the same format
 * numbers (ML Kit's, which are the plugin's), the raw value, the bytes
 * and the four corners in the upright frame. What ML Kit parsed on top
 * -- contact cards, Wi-Fi settings, calendar events -- is not filled in;
 * nothing in this app asked for it.
 */
class BarcodeDecoder(formats: List<Int>?) {
    private val reader = BarcodeReader(
        BarcodeReader.Options(
            formats = readerFormats(formats),
            tryHarder = true,
            tryRotate = true,
            tryDownscale = true,
            // The text as encoded, like ML Kit's raw value, rather than
            // a human-readable rendering of it.
            textMode = BarcodeReader.TextMode.PLAIN,
        )
    )

    /** A camera frame, rotated upright by its own rotation. */
    fun decode(image: ImageProxy): List<FoundBarcode> = reader.read(image).mapNotNull(::found)

    /** A picture, as it is. */
    fun decode(bitmap: Bitmap, rotationDegrees: Int = 0): List<FoundBarcode> =
        reader.read(bitmap, rotation = rotationDegrees).mapNotNull(::found)

    private fun found(result: BarcodeReader.Result): FoundBarcode? {
        if (result.error != null) return null
        val format = mlKitFormatOf(result.format) ?: return null
        val position = result.position
        return FoundBarcode(
            rawValue = result.text,
            rawBytes = result.bytes,
            format = format,
            corners = listOf(
                position.topLeft,
                position.topRight,
                position.bottomRight,
                position.bottomLeft,
            ),
        )
    }

    private companion object {
        /** zxing-cpp's formats by the plugin's number for them. */
        val byPluginFormat = mapOf(
            BarcodeFormats.CODE_128 to BarcodeReader.Format.CODE_128,
            BarcodeFormats.CODE_39 to BarcodeReader.Format.CODE_39,
            BarcodeFormats.CODE_93 to BarcodeReader.Format.CODE_93,
            BarcodeFormats.CODABAR to BarcodeReader.Format.CODABAR,
            BarcodeFormats.DATA_MATRIX to BarcodeReader.Format.DATA_MATRIX,
            BarcodeFormats.EAN_13 to BarcodeReader.Format.EAN_13,
            BarcodeFormats.EAN_8 to BarcodeReader.Format.EAN_8,
            BarcodeFormats.ITF to BarcodeReader.Format.ITF,
            BarcodeFormats.QR_CODE to BarcodeReader.Format.QR_CODE,
            BarcodeFormats.UPC_A to BarcodeReader.Format.UPC_A,
            BarcodeFormats.UPC_E to BarcodeReader.Format.UPC_E,
            BarcodeFormats.PDF417 to BarcodeReader.Format.PDF_417,
            BarcodeFormats.AZTEC to BarcodeReader.Format.AZTEC,
        )

        /**
         * The formats asked for, or every one ML Kit knew. zxing-cpp
         * reads a few more (DataBar, MaxiCode, Micro QR), which the plugin
         * has no number for; they stay off, so the scanner finds what it
         * found before and nothing it cannot name.
         */
        fun readerFormats(formats: List<Int>?): Set<BarcodeReader.Format> {
            val asked = formats.orEmpty().map(BarcodeFormats::fromRawValue)
            if (asked.isEmpty() || BarcodeFormats.ALL_FORMATS in asked) {
                return byPluginFormat.values.toSet()
            }
            return asked.mapNotNull(byPluginFormat::get).toSet()
        }

        fun mlKitFormatOf(format: BarcodeReader.Format): Int? =
            byPluginFormat.entries.firstOrNull { it.value == format }?.key?.intValue
    }
}

/** One barcode as found -- what ML Kit's `Barcode` carried here. */
class FoundBarcode(
    val rawValue: String?,
    val rawBytes: ByteArray?,
    val format: Int,
    val corners: List<Point>,
) {
    /** The map the Dart side reads, with the keys ML Kit's filled. */
    val data: Map<String, Any?>
        get() = mapOf(
            "corners" to corners.map { mapOf("x" to it.x.toDouble(), "y" to it.y.toDouble()) },
            "displayValue" to rawValue,
            "format" to format,
            "rawBytes" to rawBytes,
            "rawValue" to rawValue,
            "size" to size,
            // ML Kit's TYPE_TEXT, or TYPE_UNKNOWN for content that is not
            // text. The parsed types (URL, Wi-Fi, ...) are ML Kit's own.
            "type" to if (rawValue != null) 7 else 0,
        )

    private val size: Map<String, Double>
        get() {
            val xs = corners.map { it.x }
            val ys = corners.map { it.y }
            return mapOf(
                "width" to ((xs.maxOrNull() ?: 0) - (xs.minOrNull() ?: 0)).toDouble(),
                "height" to ((ys.maxOrNull() ?: 0) - (ys.minOrNull() ?: 0)).toDouble(),
            )
        }
}
