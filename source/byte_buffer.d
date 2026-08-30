module byte_buffer;

import std.exception : basicExceptionCtors, enforce;
import std.string : format;
import std.typecons;

class CapacityNotEnoughException : Exception {
    mixin basicExceptionCtors;
}

class ByteBuffer {

private:
    ubyte[] buffer;
    size_t readIndex;
    size_t writeIndex;

    /** 
     * 读取位置的标志
     */
    size_t markIndex = -1;

    /** 
     * 容量大小
     */
    size_t capacity;

public:

    static ByteBuffer create(size_t capacity) {
        return new ByteBuffer(capacity);
    }

    static ByteBuffer createWith(ubyte[] data) {
        auto bbuffer = new ByteBuffer();
        with (bbuffer) {
            buffer = data;
            readIndex = 0;
            writeIndex = data.length;
            markIndex = -1;
            capacity = data.length;
        }

        return bbuffer;
    }

    private this() {

    }

    this(size_t capacity) {
        buffer = new ubyte[capacity];
        this.readIndex = 0;
        this.writeIndex = 0;
        this.markIndex = -1;
        this.capacity = capacity;
    }

    private void check(size_t length) {
        if (this.writeIndex + length >= this.capacity) {
            enforce!CapacityNotEnoughException(
                format("write content length [%d] big than avaliable capacity [%d]", length, capacity));
        }
    }

    ubyte readByte() {
        ubyte b = buffer[this.readIndex];
        this.readIndex += 1;
        return b;
    }

    void writeByte(ubyte b) {
        check(1);
        this.buffer ~= b;
        this.writeIndex += 1;
    }

    Nullable!ubyte peekByte() {
        if (this.readIndex == this.writeIndex) {
            return Nullable!ubyte();
        }
        return Nullable!ubyte(buffer[this.readIndex]);
    }

    scope const(ubyte)[] readBytes(size_t length) {
        auto bytes = this.buffer[this.readIndex .. this.readIndex + length];
        this.readIndex += length;
        return bytes;
    }

    void writeBytes(scope const(ubyte)[] bytes) {
        check(bytes.length);
        buffer[this.writeIndex .. this.writeIndex + bytes.length] = bytes[];
        this.writeIndex += bytes.length;
    }

    bool hasRemaining() {
        return this.readIndex < this.writeIndex;
    }

    // other function
    // ===============================

    void mark() {
        markIndex = readIndex;
    }

    void reset() {
        if (-1 == markIndex) {
            return;
        }

        readIndex = markIndex;
        markIndex = -1;
    }
}
