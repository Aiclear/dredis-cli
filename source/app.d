import std.socket;
import std.stdio;
import std.outbuffer;

const string TERMINAL = "\r\n";

int main() {
    // create socket connect to redis server
    auto redisSocket = new Socket(AddressFamily.INET, SocketType.STREAM);
    scope (exit)
        redisSocket.close();

    // connect to redis server
    auto redisAddress = new InternetAddress("127.0.0.1", 6379);
    redisSocket.connect(redisAddress);
    writeln("connect to redis server success!!!");

    // handshake
    handshake(redisSocket);

    // handshake success
    ubyte[1024] buffer;
    auto readBytesLen = redisSocket.receive(buffer);
    if (Socket.ERROR == readBytesLen) {
        writeln("handshake with redis server failure!");
        return 1;
    }

    writeln("receive redis server resp: ", cast(string) buffer[0 .. readBytesLen]);

    return 0;
}

/** 
 * 握手程序
 */
void handshake(Socket reidsClientSocket) {
    // client handshake with server
    auto helloCmd = new Hello();
    auto sendBytesCnt = reidsClientSocket.send(helloCmd.encode());
    if (Socket.ERROR == sendBytesCnt) {
        writeln("handshake with redis server failure!");
        throw new Exception("handshake with redis server failed!");
    }
}

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
        buffer.write(this.COMMAND);
        buffer.write(" ");

        buffer.write(this.respVersion);
        buffer.write(" ");

        buffer.write(TERMINAL);

        return buffer.toBytes();
    }
}

class SimpleString {
    const string PLUS = "+";
}
