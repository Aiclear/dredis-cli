module redis_type;

import std.string;
import std.outbuffer;
import std.exception : enforce;
import std.typecons;
import std.conv;
import std.range : iota;
import std.bigint;

import boilerplate.autostring;

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
struct Auth {
    static const string COMMAND = "AUTH";

    string clientName = "dredis-cli";
    string password;

    this(string clientName, string password) {
        this.clientName = clientName;
        this.password = password;
    }

    this(string password) {
        this.password = password;
    }
}

struct Hello {
    // command key world
    const string COMMAND = "HELLO";
    // resp protocl version
    RespVersion respVersion = RespVersion.RESP3;
    // AUTH
    private Nullable!Auth auth_;

    @property void auth(Auth auth) {
        this.auth_ = Nullable!Auth(auth);
    }

    this(Auth auth) {
        this.auth_ = Nullable!Auth(auth);
    }

    this(RespVersion respVersion, Auth auth) {
        this.respVersion = respVersion;
        this.auth_ = Nullable!Auth(auth);
    }

    ubyte[] encode() {
        auto buffer = new OutBuffer();
        buffer.write(format("%s %s", this.COMMAND, cast(string) this.respVersion));
        if (!this.auth_.isNull()) {
            buffer.write(format("%s %s %s", Auth.COMMAND, this.auth_.get()
                    .clientName, this.auth_.get().password));
        }
        buffer.write(TERMINAL);
        return buffer.toBytes();
    }
}

interface RedisType {
    void encode(ByteBuffer buffer);
}

class SimpleString : RedisType {
    // simple string first byte
    static const ubyte PLUS = '+';

    const string str;
    mixin(GenerateToString);

    this(string str) {
        this.str = str;
    }

    override void encode(ByteBuffer buffer) {
        buffer.writeBytes(cast(ubyte[]) format("%s%s%s", PLUS, this.str, TERMINAL));
    }

    static SimpleString decode(ByteBuffer buffer) {
        return new SimpleString(cast(string) simpleTypeDecode(buffer));
    }
}

class SimpleError : RedisType {
    // simple error first byte
    static const ubyte MINUS = '-';

    const string errorMsg;
    mixin(GenerateToString);

    this(string errorMsg) {
        this.errorMsg = errorMsg;
    }

    override void encode(ByteBuffer buffer) {
        buffer.writeBytes(cast(ubyte[]) format("%s%s%s", MINUS, this.errorMsg, TERMINAL));
    }

    static SimpleError decode(ByteBuffer buffer) {
        return new SimpleError(cast(string) simpleTypeDecode(buffer));
    }
}

class Integers : RedisType {
    // integers fb
    static const ubyte COLON = ':';

    const long value;
    mixin(GenerateToString);

    this(long value) {
        this.value = value;
    }

    override void encode(ByteBuffer buffer) {
        buffer.writeBytes(cast(ubyte[]) format("%s%s%s", COLON, this.value, TERMINAL));
    }

    static Integers decode(ByteBuffer buffer) {
        return new Integers(to!long(cast(string) simpleTypeDecode(buffer)));
    }
}

// $<length>\r\n<data>\r\n
class BulkStrings : RedisType {
    static const ubyte DOLLAR = '$';

    const Nullable!string value;
    mixin(GenerateToString);

    this(string value) {
        if (value is null) {
            this.value = Nullable!string();
        } else {
            this.value = Nullable!string(value);
        }
    }

    override void encode(ByteBuffer buffer) {
        if (this.value.isNull()) {
            buffer.writeBytes(cast(ubyte[]) "$-1\r\n");
        } else {
            auto str = this.value.get();
            buffer.writeBytes(cast(ubyte[]) format("$%s\r\n%s\r\n", str.length, str));
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

    RedisType[] values;
    mixin(GenerateToString);

    this(RedisType[] values) {
        this.values = values;
    }

    override void encode(ByteBuffer buffer) {
        buffer.writeBytes(cast(ubyte[]) format("*%s\r\n", this.values.length));
        foreach (v; this.values) {
            v.encode(buffer);
        }
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

    override void encode(ByteBuffer buffer) {
        buffer.writeBytes(cast(ubyte[]) format("%s%s%s", UNDERSCORE, "", TERMINAL));
    }

    static Nulls decode(ByteBuffer buffer) {
        auto _ = simpleTypeDecode(buffer);
        return new Nulls();
    }

    override string toString() const @safe pure nothrow {
        return "null";
    }
}

class Booleans : RedisType {
    static const ubyte OCTOTHORPE = '#';

    const bool value;
    mixin(GenerateToString);

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

    override void encode(ByteBuffer buffer) {
        buffer.writeBytes(cast(ubyte[]) format("%s%s%s", OCTOTHORPE, this.value ? "t" : "f", TERMINAL));
    }
}

class Doubles : RedisType {
    static const ubyte COMMA = ',';

    const double value;
    mixin(GenerateToString);

    this(double value) {
        this.value = value;
    }

    static Doubles decode(ByteBuffer buffer) {
        return new Doubles(to!double(cast(string) simpleTypeDecode(buffer)));
    }

    override void encode(ByteBuffer buffer) {
        buffer.writeBytes(cast(ubyte[]) format("%s%s%s", COMMA, this.value, TERMINAL));
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
    mixin(GenerateToString);

    this(BigInt value) {
        this.value = value;
    }

    static BigNumbers decode(ByteBuffer buffer) {
        return new BigNumbers(BigInt(cast(string) simpleTypeDecode(buffer)));
    }

    override void encode(ByteBuffer buffer) {
        buffer.writeBytes(cast(ubyte[]) format("%s%s%s", LEFT_PARENTHESIS, this.value, TERMINAL));
    }
}

class BulkErrors : RedisType {
    static const ubyte MARK = '!';

    const string value;
    mixin(GenerateToString);

    this(string value) {
        this.value = value;
    }

    override void encode(ByteBuffer buffer) {
        buffer.writeBytes(cast(ubyte[]) format("%s%s%s", MARK, this.value, TERMINAL));
    }

    override size_t toHash() const @nogc @safe pure nothrow {
        return hashOf(this.value);
    }

    override bool opEquals(Object other) const @nogc @safe pure nothrow {
        auto be = cast(BulkErrors) other;
        return be && be.value == this.value;
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
    mixin(GenerateToString);

    this(RedisType[RedisType] value) {
        this.value = value;
    }

    override void encode(ByteBuffer buffer) {
        buffer.writeBytes(cast(ubyte[]) format("%s%s\r\n", PERCENT, this.value.length));
        foreach (k, v; this.value) {
            k.encode(buffer);
            v.encode(buffer);
        }
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
        assert(m.value.length == 2);
    }
}

void encode(immutable string command, ByteBuffer buffer) {
    RedisType[] commandArr;
    foreach (c; command.split(" ")) {
        commandArr ~= new BulkStrings(c);
    }
    new Arrays(commandArr).encode(buffer);
}

/// resp decode entrypoint
/// Params: 
///   buffer = 收到的字节数据
/// Returns: decode的redis类型数据
RedisType decode_(ByteBuffer buffer) {
    // 可能数据不完整，首先进行数据读取位置的mark
    auto idByte = buffer.readByte();

    switch (idByte) {
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
    case Maps.PERCENT:
        return Maps.decode(buffer);
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
