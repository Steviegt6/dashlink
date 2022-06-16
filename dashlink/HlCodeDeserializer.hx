package dashlink;

import haxe.io.Encoding;
import hl.UI8;
import haxe.io.BufferInput;
import haxe.io.Bytes;

typedef HlCode = {
	var version:UI8;
	var ints:Array<Int>;
	var floats:Array<Float>;
	var strings:Array<String>;
	var debugFiles:Array<String>;
}

typedef ReadChunk = {
	var version:UI8;
	var flags:UInt;
	var hasDebug:Bool;
	var nints:UInt;
	var nfloats:UInt;
	var nstrings:UInt;
	var nbytes:UInt;
	var ntypes:UInt;
	var nglobals:UInt;
	var nnatives:UInt;
	var nfunctions:UInt;
	var nconstants:UInt;
	var entrypoint:UInt;
}

typedef ReadBody = {
	var ints:Array<Int>;
    var floats:Array<Float>;
    var strings:Array<String>;
    // bytes
    var debugFiles:Array<String>;
}

class HlCodeDeserializer {
	/**
	 * The magic header of all HashLink bytecode (.hl) files.
	 * Reads as "HLB".
	 */
	public static var magicHeader(default, null) = [0x48, 0x4C, 0x42];

	/**
	 * The minimum bytecode version that may be read.
	 */
	public static var minVersion(default, null) = 4;

	/**
	 * The maximum bytecode version that may be read.
	 */
	public static var maxVersion(default, null) = 5;

	/**
	 * Deserializes a HashLink bytecode file from a `Bytes` instance.
	 * @param bytes The bytes to deserialize.
	 * @return HlCode
	 */
	public static function deserializeFromBytes(bytes:Bytes):HlCode {
		return deserializeFromBuffer(Utils.makeByteBuffer(bytes));
	}

	/**
	 * Deserializes a HashLink bytecode file from a buffer.
	 * @param buffer The buffer to read from.
	 * @param ignoreMaxVersion Whether to ignore the maximum version and deserialize newer, not-officially-supported versions.
	 * @return HlCode
	 */
	public static function deserializeFromBuffer(buffer:BufferInput, ignoreMaxVersion:Bool = false):HlCode {
		buffer.bigEndian = false;

		var code:HlCode = {
			version: 0,
			ints: [],
			floats: [],
			strings: [],
			debugFiles: null
		};

		readHeader(buffer);
		var chunk = readChunk(buffer, ignoreMaxVersion);
		var body = readBody(buffer, chunk);

        trace("Chunk: " + chunk);
        trace("Body: " + body);
        trace("Code (unused): " + code);

		return code;
	}

	public static function readHeader(buffer:BufferInput) {
		var header = [buffer.readByte(), buffer.readByte(), buffer.readByte()];

		if (!Utils.arraysEqual(header, magicHeader))
			throw "Did not match magic header \"" + magicHeader.toString() + "\", got \"" + header.toString() + "\"!";
		else
			trace("Got magic header \"" + header.toString() + "\"!");
	}

	public static function readVersion(buffer:BufferInput, ignoreMaxVersion:Bool):UI8 {
		var version = buffer.readByte();

		if (version < minVersion)
			throw "Version " + version + " is too old. Minimum version is " + minVersion + ".";

		if (version > maxVersion && !ignoreMaxVersion)
			throw "Version " + version + " is too new. Maximum version is " + maxVersion + ".";

		return version;
	}

	public static function readChunk(buffer:BufferInput, ignoreMaxVersion:Bool):ReadChunk {
		var version = readVersion(buffer, ignoreMaxVersion);
		var flags = readVarUInt(buffer);
		var chunk:ReadChunk = {
			version: version,
			flags: flags,
			hasDebug: (flags & 1) == 1,
			nints: readVarUInt(buffer),
			nfloats: readVarUInt(buffer),
			nstrings: readVarUInt(buffer),
			nbytes: version >= 5 ? readVarUInt(buffer) : -1, // -1 means unsupported
			ntypes: readVarUInt(buffer),
			nglobals: readVarUInt(buffer),
			nnatives: readVarUInt(buffer),
			nfunctions: readVarUInt(buffer),
			nconstants: readVarUInt(buffer),
			entrypoint: readVarUInt(buffer)
		};
		return chunk;
	}

	public static function readBody(buffer:BufferInput, chunk:ReadChunk):ReadBody {
		var ints = [];
		for (i in 0...chunk.nints)
			ints[i] = buffer.readInt32(); // LITTLE ENDIAN

		var floats = [];
		for (i in 0...chunk.nfloats)
			floats[i] = buffer.readFloat(); // LITTLE ENDIAN

		var strings = readStrings(buffer, chunk.nstrings);

		if (chunk.version >= 5)
			throw "TODO: Add byte reading.";

		var debugFiles = chunk.version >= 5 ? readStrings(buffer, readVarUInt(buffer)) : null;

		var body:ReadBody = {
			ints: ints,
            floats: floats,
            strings: strings,
            // bytes
            debugFiles: debugFiles
		};
		return body;
	}

	// TODO: Clean up and use bX variable naming.
	public static function readVarInt(buffer:BufferInput):Int {
		var varInt = buffer.readByte();

		if (varInt & 0x80 == 0) {
			return varInt & 0x7F;
		}

		if (varInt & 0x40 == 0) {
			var nextInt = buffer.readByte() | ((varInt & 31) << 8);

			if (varInt & 0x20 == 0) {
				return nextInt;
			} else {
				return -nextInt;
			}
		}

		var bytes = [buffer.readByte(), buffer.readByte(), buffer.readByte()];
		var retInt = ((varInt & 31) << 24) | (bytes[0] << 16) | (bytes[1] << 8) | bytes[2];

		return varInt & 0x20 == 0 ? retInt : -retInt;
	}

	public static function readVarUInt(buffer:BufferInput):UInt {
		var varInt = readVarInt(buffer);

		if (varInt < 0)
			throw "VarUInt cannot be negative! Got \"" + varInt + "\".";

		return varInt;
	}

	public static function readStrings(buffer:BufferInput, nstrings:UInt):Array<String> {
		var strings:Array<String> = [];
		var stringData:Array<Int> = [];
		var nbytes = buffer.readInt32();
		// var stringData = buffer.read(nbytes); // LITTLE ENDIAN

		var count = buffer.readInt32();
		for (i in 0...count) // LITTLE ENDIAN
			stringData[i] = buffer.readByte(); // 0;

		var acc = 0;

		for (_ in 0...nstrings) {
			var ssize = readVarUInt(buffer) + 1;
			// strings.push(stringData.getString(acc, acc + ssize));
			// var bytes = Utils.bytesFromArray(stringData.slice(acc, (acc + ssize)));
			var str = Utils.stringFromBytes(stringData.slice(acc, (acc + ssize)));
			strings.push(str);
			acc += ssize;
		}

		return strings;
	}

	// Figured out you can just specify endianness for the input lol.
	/*// https://stackoverflow.com/a/13001446
		// Dunno how endianness works with Haxe and I don't want to have to find out the hard way, so using this to be safe.
		public static function readLittleEndianInt(buffer:BufferInput):Int {
			var b1 = buffer.readByte();
			var b2 = buffer.readByte();
			var b3 = buffer.readByte();
			var b4 = buffer.readByte();
			return b1 | (b2 << 8) | (b3 << 16) | (b4 << 24);
		}

		public static function readLittleEndianFloat(buffer:BufferInput):Float {} */
}