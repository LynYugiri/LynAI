# LynAI 安全设备协议 v1

本文定义 LynAI v1 的 canonical 编码、设备身份和设备注册，并记录后续 LAN TLS 绑定与加密备份的算法决策。关键字 **MUST**、**MUST NOT**、**SHOULD**、**MAY** 按 RFC 2119 / RFC 8174 理解。

> 实现状态：设备 Ed25519 身份、账号认证后的 enrollment、变更与 blob 请求签名、后端验证和幂等提交、LAN TLS/SPKI/设备证明，以及加密备份信封已实现。

## 1. 算法与文本编码

| 用途 | v1 决策 |
|------|---------|
| 设备身份与签名 | Ed25519；公钥 32 bytes，签名 64 bytes。 |
| 哈希 | SHA-256。 |
| 二进制 JSON 字段 | RFC 4648 base64url，无 `=` padding，必须 canonical。 |
| `deviceId` | RFC 4648 Base32，小写，无 `=` padding。 |
| 后续 LAN 传输 | TLS 1.3；TLS SPKI 由设备 Ed25519 身份签名绑定。 |
| 备份 KDF | Argon2id。 |
| 备份 AEAD | XChaCha20-Poly1305。 |

v1 不存在长期 X25519 设备身份。若未来某次握手需要临时密钥协商，临时私钥不得持久化，也不得成为设备标识。私钥、challenge、session token、备份口令和派生密钥 MUST NOT 写入日志。

base64url 解码器 MUST 拒绝 padding、标准 Base64 的 `+`/`/`、空值（字段明确允许时除外）、无效尾部位和任何解码后重新编码不等于原文本的输入。

## 2. Canonical Binary Encoding（CBE1）

CBE1 对象是按 tag 严格递增的字段串联：

```text
field  = tag:u16-big-endian || length:u32-big-endian || value
object = field*
```

规则：

1. tag 必须严格递增；重复、乱序和 schema 未定义的 tag MUST 被拒绝。
2. length 是 value 的 byte 长度。解析器必须在分配前检查对象和字段上限。
3. 整数使用字段表指定的固定宽度 big-endian 编码。
4. 文本使用合法 UTF-8，不含 BOM；本协议不隐式执行 Unicode normalization。
5. domain separator 是给定 ASCII 文本后追加一个 NUL byte `00`。
6. 签名输入是 `domain || CBE1 object` 的原始 bytes，不是其 hash、hex 或 base64 文本。

## 3. 设备身份与 `deviceId`

客户端按用途生成 Ed25519 identity key。LAN 使用独立的 `lan:v1` scope；云端 identity MUST 按规范化 backend origin（scheme + host + effective port）和 `userId` 共同作用域。私钥 MUST 只保存在平台安全存储 `SecretStore`，不得写入 SharedPreferences、业务数据库、日志或备份。公钥可以公开和登记。

```text
digest   = SHA-256(ed25519PublicKey32)
deviceId = lowercase-base32-without-padding(digest)
```

完整 32-byte SHA-256 digest 编码后，`deviceId` 固定为 52 个字符，正则为：

```text
^[a-z2-7]{52}$
```

服务端 MUST 从提交的 Ed25519 公钥重新派生并比较 `deviceId`。设备表以该确定性 `deviceId` 为主键，不生成随机设备主 ID。`deviceId` 和 Ed25519 公钥均须全局唯一。同一 backend origin 下的不同账号以及不同 backend origin MUST 使用独立 identity 和独立安全存储命名空间；切换账号或后端时不得复用其他 scope 的 identity 进行 enrollment。LAN identity 不得用于云 enrollment/signing。

删除并重新生成 identity key 会产生新设备。已撤销 identity 不得通过普通幂等 enrollment 静默恢复。

## 4. 设备注册（Enrollment）

注册只发生在账号 access token 已认证后。客户端先提交拟注册数据取得一次性 challenge：

```json
POST /devices/challenge
{
  "deviceId": "<52-char base32>",
  "publicKey": "<43-char raw base64url>",
  "displayName": "<UTF-8 text>",
  "platform": "linux",
  "protocolVersion": 1
}
```

约束：Ed25519 公钥恰好 32 bytes；`displayName` 为 1..64 UTF-8 bytes、首尾无空白；`platform` 匹配 `^[a-z0-9._-]{1,32}$`；协议版本必须为 1。

服务端返回：

```json
{
  "challengeId": "<32-char raw base64url>",
  "challenge": "<43-char raw base64url, 32 bytes>",
  "userId": "<authenticated stable user ID>",
  "sessionId": "<authenticated session ID>",
  "expiresAt": "<RFC 3339 timestamp>"
}
```

challenge 记录 MUST 绑定认证 user ID、session ID、`deviceId`、公钥、显示名称、平台和协议版本，并且只保存 challenge 原始值的 SHA-256。challenge 有效期为 5 分钟且只能消费一次。

### 4.1 签名消息

Domain：`LynAI/v1/enrollment\x00`

| Tag | 名称 | 编码 | 约束 |
|-----|------|------|------|
| 1 | `protocolVersion` | `u16` | `1`。 |
| 2 | `challengeId` | ASCII | 32 bytes，服务端返回值。 |
| 3 | `challenge` | raw bytes | 32 bytes。 |
| 4 | `userId` | UTF-8 | 必须等于认证用户。 |
| 5 | `sessionId` | UTF-8 | 必须等于认证 session。 |
| 6 | `deviceId` | ASCII | 52 bytes。 |
| 7 | `ed25519PublicKey` | raw bytes | 32 bytes。 |
| 8 | `displayName` | UTF-8 | 1..64 bytes。 |
| 9 | `platform` | ASCII | 1..32 bytes。 |

```text
enrollmentMessage = "LynAI/v1/enrollment\x00" || CBE1(fields 1..9)
signature = Ed25519-Sign(identityPrivateKey, enrollmentMessage)
```

客户端随后提交与 challenge 请求完全相同的拟注册字段，加上 `challengeId`、`challenge` 和无 padding base64url `signature`。服务端 MUST：

1. 严格验证所有长度、文本规则和 canonical base64url。
2. 从公钥重新派生 `deviceId`。
3. 用认证上下文中的 user ID/session ID 重建消息，不信任客户端另行提交认证身份。
4. 验证 challenge 记录绑定的全部拟注册字段、摘要、有效期和未消费状态。
5. 验证 Ed25519 signature 后，在同一事务中原子消费 challenge 并登记设备。
6. 同一用户重复登记同一未撤销 key/device MUST 幂等成功，并可更新当前 session、显示名称和平台。
7. key/device 已属于另一用户或 identity 已撤销时 MUST 冲突失败；多账号客户端必须改用该账号自己的 identity，不能把同一 key/device 重新归属。

客户端的自动注册是 best effort：离线、未配置后端或不提供设备端点的旧后端不得阻塞本地启动、登录或旧功能。

## 5. 同步变更请求签名与幂等

同步仍使用 Bearer token，设备签名不替代 TLS。v1 签名适用于 `POST /sync/changes`、兼容别名 `POST /sync/v1/changes` 和 `POST /sync/blobs/:sha256`。canonical target 使用服务端路由模板，不含 scheme、authority、query 或 fragment。blob 的 body hash 必须是实际传输的原始 octet-stream bytes；同一 blob 重试必须复用稳定 request ID 和完全相同的 body bytes。

请求头：

| Header | 约束 |
|--------|------|
| `X-LynAI-Protocol` | 精确为 `1`。 |
| `X-LynAI-Device-ID` | 当前认证用户、当前 session 下已登记且未撤销的 52 字符 device ID。 |
| `X-LynAI-Timestamp` | Unix epoch milliseconds 的十进制文本。 |
| `X-LynAI-Request-ID` | 24 个随机 bytes 的 canonical base64url，固定 32 字符。 |
| `X-LynAI-Body-SHA256` | HTTP 实际 body bytes 的 SHA-256 小写 64 字符 hex。 |
| `X-LynAI-Signature` | 64-byte Ed25519 signature 的 canonical base64url。 |

Domain：`LynAI/v1/sync-request\x00`

| Tag | 名称 | 编码 |
|-----|------|------|
| 1 | `protocolVersion` | `u16`，值为 1。 |
| 2 | `userId` | UTF-8，认证上下文中的稳定用户 ID 十进制文本。 |
| 3 | `sessionId` | UTF-8，认证 access token 的 session ID。 |
| 4 | `deviceId` | ASCII，52 bytes。 |
| 5 | `timestampMs` | `u64` big-endian。 |
| 6 | `requestId` | ASCII，32 bytes。 |
| 7 | `method` | ASCII，精确为 `POST`。 |
| 8 | `canonicalTarget` | ASCII，路由模板。 |
| 9 | `bodySha256` | raw bytes，32 bytes。 |

```text
syncRequestMessage = "LynAI/v1/sync-request\x00" || CBE1(fields 1..9)
signature = Ed25519-Sign(identityPrivateKey, syncRequestMessage)
```

body schema：

```json
{
  "requestId": "<same value as X-LynAI-Request-ID>",
  "changes": [{
    "changeId": "<stable client-generated ID, 1..128 bytes>",
    "table": "messages",
    "op": "upsert",
    "recordId": "message-1",
    "data": {"id":"message-1"},
    "clientCreatedAt": "<RFC 3339 timestamp>"
  }]
}
```

服务端 MUST 在一个数据库事务中分配 seq、插入新 change、更新用户 latest seq，并保存精确 HTTP response bytes。`(userId, changeId)` 全局唯一于该用户：table/op/recordId/data/clientCreatedAt 相同的 change 可跨请求或设备返回原 seq ACK，不同内容冲突；首次接受该 change 的签名设备记入 `deviceId` 审计字段。`(userId, requestId)` 是 durable request key：相同 operation 和 body hash 必须返回精确原始 status、content type 和 body；不同 operation 或 body hash 必须返回 HTTP 409。响应包含每个 change 的 `changeId` 和已分配 `seq`。

客户端必须按“规范化后端 origin + 稳定 user ID”隔离云同步游标、Outbox 和冲突状态。切换账号不得确认、上传或应用另一账号作用域中的变更。兼容旧后端时，若成功上传响应中的 `changes` 条目没有可用 `changeId`，客户端可把响应视为旧式整批 ACK，并仅确认本次提交时捕获的精确 Outbox 快照；不得据此确认随后产生的新 mutation。

业务 table allowlist 包含 `shared_settings` 和 `synced_model_configs`。`shared_settings` 的 v1 record ID 固定为 `app-settings`，payload 必须是 `SharedSettingsV1`，不得上传完整本地设置 JSON。`synced_model_configs` 以 Provider ID 为 record ID，payload 必须是 `SyncedModelConfigV1`，不得包含 `apiKey`、`apiKeySecretRef` 或其他秘密字段；托管 Relay Provider 不得由客户端上传。

签名时间戳必须在服务端配置的 clock skew 内。未知设备、非当前 session 设备、已撤销设备、无效 body hash 或签名均被拒绝。客户端云同步在发送变更或 blob 前 MUST 完成 enrollment，并且每个上传请求 MUST 携带完整签名头；客户端不得在 enrollment、签名构造或签名验证失败时降级为 unsigned 请求。

### 5.1 Sync 固定测试向量

沿用第 8 节测试 seed/public key，并使用：

```text
userId: 42
sessionId: session-vector-1
deviceId: kzdvvj2umnduyauf35o36k6kw462mujvra46tn3uqgzovmihocga
timestampMs: 1700000000123
requestId: AAECAwQFBgcICQoLDA0ODxAREhMUFRYX
method: POST
canonicalTarget: /sync/changes
bodySha256: 000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f
```

```text
sync request message hex:
4c796e41492f76312f73796e632d72657175657374000001000000020001000200000002343200030000001073657373696f6e2d766563746f722d310004000000346b7a6476766a32756d6e64757961756633356f33366b366b773436326d756a7672613436746e337571677a6f766d69686f6367610005000000080000018bcfe5687b00060000002041414543417751464267634943516f4c4441304f4478415245684d5546525958000700000004504f535400080000000d2f73796e632f6368616e676573000900000020000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f

Ed25519 signature base64url:
ijPzt7fLykodsX18MwAXhwlvPUMMdtWqraTQUUwREshEkGTXxu09x8Ziz8a3dqkU2dCL6GVLgRoBKxzcGXSaCw
```

## 6. 后续 LAN TLS 1.3 绑定

LAN 连接必须使用 TLS 1.3。配对记录绑定的是 TLS 证书 `SubjectPublicKeyInfo` DER 的 SHA-256：

```text
spkiPin = SHA-256(certificate.SubjectPublicKeyInfoDER)
```

TLS SPKI 必须由已登记的 Ed25519 device identity 对明确 domain-separated、包含 SPKI hash、设备 ID、有效期和上下文的 canonical 消息签名。验证方先验证 Ed25519 绑定，再按配对策略验证 TLS 1.3 连接和 SPKI。不得用长期 X25519 identity 替代该绑定，也不得把普通证书指纹当作 SPKI pin。

具体 LAN offer、轮换和人工确认 schema 尚未冻结，后续版本必须补充固定向量后实现。

## 7. 加密备份

普通 ZIP 备份 MUST NOT 包含 API key。只有用户明确选择“包含 API Key”时，导出器才在内层 ZIP 增加 `secrets/model_api_keys.json`，并且 MUST 随即把该 ZIP 的精确 bytes 放入本节信封。设备身份私钥、账号 access/refresh token、challenge、session token、LAN 私钥和其他设备私有密钥 MUST NOT 进入任何备份。

### 7.1 信封

所有整数为 big-endian。信封是以下字段的直接串联，不允许扩展字段、padding 或 trailing bytes：

```text
magic[8]          = ASCII "LYNAIBK1"
version:u16       = 1
flags:u16         = 0
memoryKiB:u32
iterations:u32
parallelism:u16
saltLength:u16    = 16
nonceLength:u16   = 24
tagLength:u16     = 16
plaintextLength:u64
ciphertextLength:u64 = plaintextLength
salt[16]
nonce[24]
ciphertext[plaintextLength]
tag[16]
```

从 `magic` 到 `nonce` 末尾的全部 header bytes 是 XChaCha20-Poly1305 AAD。明文是现有 ZIP 导出的精确 bytes，不重新编码、不压缩第二次。Argon2id 使用版本 0x13，从 UTF-8 口令和 header 中的 salt 派生 32-byte key。v1 导出参数为 `memoryKiB=19456`、`iterations=2`、`parallelism=1`；导入器在运行 KDF 前必须拒绝 memory 不在 19456..262144 KiB、iterations 不在 2..10、parallelism 不在 1..4、memory 小于 `8 * parallelism`、口令超过 1024 UTF-8 bytes、明文超过 512 MiB、长度不一致、未知版本/flags 或错误固定长度。

认证 tag 验证成功前不得解析 ZIP。错误口令、header/ciphertext/tag 篡改、截断和其他信封损坏对用户只返回同一个“密码错误或备份文件已损坏”错误，避免形成口令或格式 oracle。未加密 ZIP 由 ZIP 读取入口处理，不能伪装成加密信封；带 `secrets` manifest 的 ZIP 若未经过已认证信封必须拒绝。

### 7.2 API Key 分区

`secrets/model_api_keys.json` 固定为：

```json
{
  "type": "lynai.model-api-keys",
  "version": 1,
  "keys": {"<modelId>": "<apiKey>"}
}
```

只允许 `type`、`version`、`keys` 三个字段。恢复时 key 按 model ID 注入模型配置并由 `ModelConfigRepository` 写入 `SecretStore`；非秘密模型 JSON 只保留 `apiKeySecretRef`。当前备份 schema 接受前一版 schema 5 ZIP，但其中历史明文 `apiKey` 字段会被忽略，不会恢复到安全存储。

## 8. Enrollment 固定测试向量

以下密钥仅用于测试。

```text
Ed25519 seed:
000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f

Ed25519 public key:
03a107bff3ce10be1d70dd18e74bc09967e4d6309ba50d5f1ddc8664125531b8

protocolVersion: 1
challengeId: AAECAwQFBgcICQoLDA0ODxAREhMUFRYX
challenge:
000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f
userId: 42
sessionId: session-vector-1
displayName: LynAI Test Device
platform: linux

deviceId:
kzdvvj2umnduyauf35o36k6kw462mujvra46tn3uqgzovmihocga

enrollment message hex:
4c796e41492f76312f656e726f6c6c6d656e7400000100000002000100020000002041414543417751464267634943516f4c4441304f4478415245684d5546525958000300000020000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f000400000002343200050000001073657373696f6e2d766563746f722d310006000000346b7a6476766a32756d6e64757961756633356f33366b366b773436326d756a7672613436746e337571677a6f766d69686f63676100070000002003a107bff3ce10be1d70dd18e74bc09967e4d6309ba50d5f1ddc8664125531b80008000000114c796e41492054657374204465766963650009000000056c696e7578

Ed25519 signature base64url:
6Mr7DylNhi4lvmRlcAkODJoRmQx0XbJlocqFS2oWate0HRz-jM_0ZbblRzaBZvMHL4R-hyrMPcFAYKyF7PjZDg
```

## 9. 版本与拒绝策略

v1 解析器必须 fail closed：未知协议版本、未知字段、非 canonical 编码、错误长度、无效 UTF-8、`deviceId` 派生不匹配、无效签名或 challenge 绑定不匹配均不得降级为未签名注册。未来不兼容变更必须使用新协议版本和 domain separator。
