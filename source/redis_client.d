module redis_client;

import std.socket;

struct RedisAddress {
}

class RedisClient {

    public static RedisClient connect(string ip, ushort port) {
        return new RedisClient();
    }
}

private RedisClient handshake(string ip, ushort port) {
    auto clientSocket = new Socket(AddressFamily.INET, SocketType.STREAM, ProtocolType.TCP);

    // connect to redis server with tcp commu
    auto redisServerAddr = new InternetAddress(ip, port);
    clientSocket.connect(redisServerAddr);

    // send handshake message
    return null;
}
