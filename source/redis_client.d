module redis_client;

import std.socket;
import std.exception;

import redis_type;
import byte_buffer;

// client default buffer size 2MB
const size_t DEFAULT_CLIENT_BUFFER_SIZE = 2 * 1024 * 1024;

class RedisClient {

    private XSocket socket;
    private ByteBuffer buffer;
    private ServerInfo serverInfo;

    this(Socket socket) {
        this.socket = new XSocket(socket);
        this.buffer = ByteBuffer.create(DEFAULT_CLIENT_BUFFER_SIZE);
    }

    static RedisClient connect(string ip, ushort port) {
        return handshake(ip, port, null);
    }

    static RedisClient connect(string ip, ushort port, string password) {
        return handshake(ip, port, password);
    }
}

struct ServerInfo {
    const string server;
    const string version_;
    const string proto;
}

private RedisClient handshake(string ip, ushort port, string password) {
    auto clientSocket = new Socket(AddressFamily.INET, SocketType.STREAM, ProtocolType.TCP);

    // connect to redis server with tcp commu
    auto redisServerAddr = new InternetAddress(ip, port);
    clientSocket.connect(redisServerAddr);
    // build hello command 
    Hello helloCmd;
    if (password.length) {
        helloCmd.auth = Auth(password);
    }

    // send hello command and confirm resp version
    auto sendRes = clientSocket.send(helloCmd.encode());
    if (Socket.ERROR == sendRes) {
        enforce!Exception("send hello command to server recv error");
    }

    // handle hello cmd response
    ubyte[] tmpBuf = new ubyte[1024];
    auto c = clientSocket.receive(tmpBuf);
    if (Socket.ERROR == c) {
        enforce!Exception("receive data from server error");
    }
    ByteBuffer tmpBuffer = ByteBuffer.createWith(tmpBuf);
    auto redisType = decode_(tmpBuffer);

    debug {
        import std.stdio : writefln;

        writefln("%s", redisType);
    }

    // init redis client by sever response info
    return new RedisClient(clientSocket);
}

class XSocket {
    private Socket socket;

    this(Socket socket) {
        this.socket = socket;
    }

    public void read(ByteBuffer buffer) {

    }

    public void write(ByteBuffer buffer) {

    }
}
