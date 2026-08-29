module redis_type;

import std.string : format;
import std.outbuffer;
import std.exception : enforce;
import std.typecons;
import std.conv;
import std.range : iota;
import std.bigint;

import byte_buffer;

const string TERMINAL = "\r\n";
const ubyte CR = '\r';
const ubyte LF = '\n';

/** 
 * resp protocol version
 */
enum RespVersion {
    RESP2 = "2",
    RESP3 = "3"
}

/** 
 * connect auth info
 */
class Auth {
private:
    string clientName = "dredis-cli";
    string password;

public:
    this(string clientName, string password) {
        this.clientName = clientName;
        this.password = password;
    }

    this(string password) {
        this.password = password;
    }
}

class Hello {
    // command key world
    const string COMMAND = "HELLO";
    // resp protocl version
    RespVersion respVersion = RespVersion.RESP3;
    // AUTH
    Auth auth;

    this() {
    }

    this(Auth auth) {
        this.auth = auth;
    }

    this(RespVersion respVersion, Auth auth) {
        this.respVersion = respVersion;
        this.auth = auth;
    }

    ubyte[] encode() {
        auto buffer = new OutBuffer();
        buffer.write(format("%s %s \r\n", this.COMMAND, this.respVersion));
        return buffer.toBytes();
    }
}

interface RedisType {
}

class SimpleString : RedisType {
    // simple string first byte
    static const ubyte PLUS = '+';

    private string str;

    this(string str) {
        this.str = str;
    }

    static SimpleString decode(ByteBuffer buffer) {
        return new SimpleString(cast(string) simpleTypeDecode(buffer));
    }
}

class SimpleError : RedisType {
    // simple error first byte
    static const ubyte MINUS = '-';

    string errorMsg;

    this(string errorMsg) {
        this.errorMsg = errorMsg;
    }

    static SimpleError decode(ByteBuffer buffer) {
        return new SimpleError(cast(string) simpleTypeDecode(buffer));
    }
}

class Integers : RedisType {
    // integers fb
    static const ubyte COLON = ':';

    const long value;

    this(long value) {
        this.value = value;
    }

    static Integers decode(ByteBuffer buffer) {
        return new Integers(to!long(cast(string) simpleTypeDecode(buffer)));
    }
}

// $<length>\r\n<data>\r\n
class BulkStrings : RedisType {
    static const ubyte DOLLAR = '$';

    const Nullable!string value;

    this(string value) {
        if (value is null) {
            this.value = Nullable!string();
        } else {
            this.value = Nullable!string(value);
        }
    }

    static BulkStrings decode(ByteBuffer buffer) {
        // read data length
        auto length = to!long(cast(string) simpleTypeDecode(buffer));
        if (-1 == length) {
            return new BulkStrings(null);
        }

        auto bs = new BulkStrings(cast(string) buffer.readBytes(length));

        buffer.readByte();
        buffer.readByte();

        return bs;
    }

    unittest {
        auto buffer = new ByteBuffer(512);
        buffer.writeBytes(cast(ubyte[]) "5\r\nhello\r\n");

        auto bs = BulkStrings.decode(buffer);
        assert(bs.value == "hello");
        assert(!buffer.hasRemaining());
    }
}

class Arrays : RedisType {
    static const ubyte ASTERISK = '*';

    const RedisType[] values;

    this(RedisType[] values) {
        this.values = values;
    }

    static Arrays decode(ByteBuffer buffer) {
        auto eleNum = to!uint(cast(string) simpleTypeDecode(buffer));

        RedisType[] elements = new RedisType[eleNum];
        foreach (i; iota(eleNum)) {
            elements ~= decode(buffer);
        }

        return new Arrays(elements);
    }
}

class Nulls : RedisType {
    static const ubyte UNDERSCORE = '_';

    static Nulls decode(ByteBuffer buffer) {
        auto _ = simpleTypeDecode(buffer);
        return new Nulls();
    }
}

class Booleans : RedisType {
    static const ubyte OCTOTHORPE = '#';

    const bool value;

    this(bool value) {
        this.value = value;
    }

    static Booleans decode(ByteBuffer buffer) {
        auto v = cast(string) simpleTypeDecode(buffer);
        if ("t" == v) {
            return new Booleans(true);
        } else {
            return new Booleans(false);
        }
    }
}

class Doubles : RedisType {
    static const ubyte COMMA = ',';

    const double value;

    this(double value) {
        this.value = value;
    }

    static Doubles decode(ByteBuffer buffer) {
        return new Doubles(to!double(cast(string) simpleTypeDecode(buffer)));
    }

    unittest {
        auto buffer = new ByteBuffer(512);
        buffer.writeBytes(cast(ubyte[]) ",1.23\r\n");
        buffer.readByte();
        auto d = Doubles.decode(buffer);
        assert(d.value == 1.23);
    }
}

class BigNumbers : RedisType {
    static const ubyte LEFT_PARENTHESIS = '(';

    const BigInt value;

    this(BigInt value) {
        this.value = value;
    }

    static BigNumbers decode(ByteBuffer buffer) {
        return new BigNumbers(BigInt(cast(string) simpleTypeDecode(buffer)));
    }
}

class BulkErrors : RedisType {
    static const ubyte MARK = '!';

    const string value;

    this(string value) {
        this.value = value;
    }

    static BulkErrors decode(ByteBuffer buffer) {
        auto len = to!uint(cast(string) simpleTypeDecode(buffer));
        auto errors = cast(string) buffer.readBytes(len);

        buffer.readByte();
        buffer.readByte();

        return new BulkErrors(errors);
    }
}

class Maps : RedisType {
    static const ubyte PERCENT = '%';

    RedisType[RedisType] value;

    this(RedisType[RedisType] value) {
        this.value = value;
    }

    static Maps decode(ByteBuffer buffer) {
        auto size = to!uint(cast(string) simpleTypeDecode(buffer));

        RedisType[RedisType] v;
        foreach (i; iota(size)) {
            auto key = decode_(buffer);
            auto val = decode_(buffer);

            v[key] = val;
        }

        return new Maps(v);
    }

    unittest {
        import std.stdio;

        auto buffer = new ByteBuffer(512);
        buffer.writeBytes(cast(ubyte[]) "%2\r\n+first\r\n:1\r\n+second\r\n:2\r\n");
        buffer.readByte();
        auto m = Maps.decode(buffer);
        assert(m.value.length != 0);
        writeln(m.value);
    }
}

/// resp decode entrypoint
/// Params: 
///   buffer = 收到的字节数据
/// Returns: decode的redis类型数据
RedisType decode_(ByteBuffer buffer) {
    // 可能数据不完整，首先进行数据读取位置的mark
    auto idByte = buffer.peekByte();
    if (idByte.isNull) {
        enforce!Exception("cannot decode empty buffer");
    } else {
        buffer.readByte();
    }

    switch (idByte.get) {
    case SimpleString.PLUS:
        return SimpleString.decode(buffer);
    case SimpleError.MINUS:
        return SimpleError.decode(buffer);
    case Integers.COLON:
        return Integers.decode(buffer);
    case BulkStrings.DOLLAR:
        return BulkStrings.decode(buffer);
    case Arrays.ASTERISK:
        return Arrays.decode(buffer);
    case Nulls.UNDERSCORE:
        return Nulls.decode(buffer);
    case Booleans.OCTOTHORPE:
        return Booleans.decode(buffer);
    case Doubles.COMMA:
        return Doubles.decode(buffer);
    case BigNumbers.LEFT_PARENTHESIS:
        return BigNumbers.decode(buffer);
    default:
        return null;
    }
}

// tool function 
private ubyte[] simpleTypeDecode(ByteBuffer buffer) {
    // 读取字节作为字符串
    ubyte[] ubyteArr;
    // 读取状态记录
    auto readCR = false;

    // \r\n
    while (buffer.hasRemaining) {
        auto tByte = buffer.readByte();
        if (readCR) {
            if (LF == tByte) {
                break;
            } else {
                enforce!Exception("cannot contain \\r or \\n");
            }
        } else {
            if (LF == tByte) {
                enforce!Exception("cannot contain \\r or \\n");
            }
        }
        if (CR == tByte) {
            readCR = true;
        }

        if (!readCR) {
            ubyteArr ~= tByte;
        }
    }

    return ubyteArr;
}
