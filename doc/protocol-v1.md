# LynAI 安全设备协议 v1

本文定义 LynAI v1 的 canonical 编码、设备身份和设备注册，并记录 LAN TLS 绑定、加密备份和客户端 Agent 所依赖的 canonical relay 边界。关键字 **MUST**、**MUST NOT**、**SHOULD**、**MAY** 按 RFC 2119 / RFC 8174 理解。

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

同步仍使用 Bearer token，设备签名不替代 TLS。v1 签名适用于 `POST /sync/changes`、兼容别名 `POST /sync/v1/changes`、`POST /sync/blobs/:sha256`、`POST /sync/manage/purge` 和 `POST /sync/manage/operations/:id/ack`。canonical target 使用服务端路由模板，不含 scheme、authority、query 或 fragment；后两个管理路由的 canonical target 精确为 `/sync/manage/purge` 和 `/sync/manage/operations/:id/ack`，不得把实际 operation ID 代入模板。blob 的 body hash 必须是实际传输的原始 octet-stream bytes；同一写请求重试必须复用稳定 request ID 和完全相同的 body bytes。

请求头：

| Header | 约束 |
|--------|------|
| `X-LynAI-Protocol` | 精确为 `1`。 |
| `X-LynAI-Device-ID` | 当前认证用户、当前 session 下已登记且未撤销的 52 字符 device ID。 |
| `X-LynAI-Timestamp` | Unix epoch milliseconds 的十进制文本。 |
| `X-LynAI-Request-ID` | 24 个随机 bytes 的 canonical base64url，固定 32 字符。 |
| `X-LynAI-Body-SHA256` | HTTP 实际 body bytes 的 SHA-256 小写 64 字符 hex。 |
| `X-LynAI-Expected-Generation` | 当前云端 generation 的十进制正整数。 |
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
| 10 | `expectedGeneration` | `u64` big-endian，值至少为 1。 |

```text
syncRequestMessage = "LynAI/v1/sync-request\x00" || CBE1(fields 1..10)
signature = Ed25519-Sign(identityPrivateKey, syncRequestMessage)
```

body schema：

```json
{
  "requestId": "<same value as X-LynAI-Request-ID>",
  "expectedGeneration": 1,
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

JSON 签名写请求的 body `expectedGeneration`、`X-LynAI-Expected-Generation` 和 tag 10 MUST 完全一致。blob 上传没有 JSON generation 字段，只在 header 与 tag 10 中携带同一个值。

服务端 MUST 在一个数据库事务中分配 seq、插入新 change、更新用户 latest seq、维护当前记录投影及其 blob 引用，并保存精确 HTTP response bytes。`(userId, changeId)` 全局唯一于该用户：table/op/recordId/data/clientCreatedAt 相同的 change 可跨请求或设备返回原 seq ACK，不同内容冲突；首次接受该 change 的签名设备记入 `deviceId` 审计字段。`(userId, requestId)` 是 durable request key：相同 operation 和 body hash 必须返回精确原始 status、content type 和 body；不同 operation 或 body hash 必须返回 HTTP 409。响应包含每个 change 的 `changeId` 和已分配 `seq`。所有 upsert 的 `data` 必须是 JSON object，且 `data.id` 必须严格等于 `recordId`。

客户端必须按“规范化后端 origin + 稳定 user ID”隔离云同步游标、Outbox 和冲突状态。切换账号不得确认、上传或应用另一账号作用域中的变更。兼容旧后端时，若成功上传响应中的 `changes` 条目没有可用 `changeId`，客户端可把响应视为旧式整批 ACK，并仅确认本次提交时捕获的精确 Outbox 快照；不得据此确认随后产生的新 mutation。

业务 table allowlist 额外包含 `knowledge_bases`、`knowledge_categories`、`knowledge_entries`、`knowledge_sources`、`knowledge_explanations`。知识子表的 payload 必须携带非空 `knowledgeBaseId`，所有知识时间字段均为带时区的 RFC3339 时间。当前客户端不上传 `knowledge_settings`，也不在 `knowledge_categories` payload 中发送 `isDefault`；为兼容旧服务端历史流，下载到 record ID 为 `global` 的 `knowledge_settings` change 时客户端将其作为 no-op 确认并推进游标，旧类别 payload 中的 `isDefault` 被忽略。`global` 仍是保留 ID，不得用作 `knowledge_bases` 的 record ID。旧 planning 名 `schedules`、`todo_lists`、`todo_items` 不再接受。`shared_settings` 的 v1 record ID 固定为 `app-settings`，payload 必须是 `SharedSettingsV1`，不得上传完整本地设置 JSON。`synced_model_configs` 以 Provider ID 为 record ID，payload 必须是 `SyncedModelConfigV1`，不得在任何嵌套 Map/List 中包含 `apiKey`、`apiKeySecretRef` 或其他 secret-like key；托管 Relay Provider 不得由客户端上传。

签名时间戳必须在服务端配置的 clock skew 内。未知设备、非当前 session 设备和已撤销设备分别返回 `unknown_device`、`device_session_mismatch`、`revoked_device`；无效 body hash 或签名返回 `invalid_signed_request`。客户端云同步在发送变更或 blob 前 MUST 完成 enrollment，并且每个上传请求 MUST 携带完整签名头；客户端不得在 enrollment、签名构造或签名验证失败时降级为 unsigned 请求。

`GET /sync/status` 和别名 `GET /sync/index/status` 返回 `lastSeq`、`generation`、`indexRevision`、`minAvailableSeq`、兼容字段 `blobCount`、`usage`、`limits` 和 additive `capabilities`。`capabilities` 当前包含 `index`、`selectivePurge`、`fullPurge`、`operationAck`；旧后端省略该 object 时客户端按旧协议安全降级。capabilities object 一旦存在，已出现的 capability 值必须是 JSON boolean，非法类型必须失败关闭；客户端分别门控索引浏览、selective purge、full purge 和 operation ACK，不得用任一 capability 代替其他 capability。若后端广告 capabilities，新字段缺失、非法或分页间 generation/indexRevision 不一致时客户端必须失败关闭且不得推进 cursor。`usage` 至少包含当前 `recordCount`、`blobCount`、`blobBytes`、`blobRefCount`。新用户 `generation=1`、`minAvailableSeq=0`；`indexRevision` 是每用户单调递增的 projection revision，普通 change 至少推进到最新 seq，purge 额外推进一次，不能假定它始终等于 `lastSeq`。

### 5.1 云端索引与 purge/reseed

`GET /sync/index/objects` 必须传 `category` 和 `expectedIndexRevision`，可选 `after` 与 `limit`（1..500）。服务端按 `objectId` 严格升序 keyset 分页；`after` 是 opaque canonical base64url cursor。整个分页过程必须固定同一个 revision，若当前 revision 不等于 expected 值返回 HTTP 409 `index_revision_conflict`。`GET /sync/index/objects/:category/:objectId` 返回对象汇总和组成该对象的全部当前 projection records。

稳定 category 映射包含当前知识表 `knowledge_bases`、`knowledge_categories`、`knowledge_entries`、`knowledge_sources`、`knowledge_explanations` 到 `knowledge`。`knowledge_bases` 的 objectId 为 record ID，知识子表的 objectId 为 payload 中的 `knowledgeBaseId`，缺失时拒绝该 change；历史 `knowledge_settings/global` 仅用于下载兼容，不参与客户端当前数据选择、快照或 reseed。其他既有表仍按各自父字段或 record ID 确定 objectId。

`POST /sync/manage/purge/preview` 接受 `expectedIndexRevision` 和 selector，不修改数据。签名 `POST /sync/manage/purge` 还必须包含与签名头一致的 `requestId`。selector schema 为 `{"type":"object","category":"messages","objectId":"conversation-1"}`、`{"type":"category","category":"notes"}` 或 `{"type":"all"}`，未知字段和尾随 JSON 均拒绝。selective purge 删除匹配 projection、对应历史 change 和 projection blob refs，创建 `kind=selective` pending operation；其 preview 与实际删除必须使用同一历史归属语义。category 由稳定 table 映射确定；object membership 对每条 upsert 从该条 payload 和 table 语义独立派生，缺少 data 的 delete 继承同一 table/recordId 最近一次 upsert 的 membership。记录后来迁移到其他 object、当前 projection 已删除或 delete 后无当前行时，不得导致目标 object 的较早历史残留。all purge 删除该用户全部 projection/change/blob refs，递增 generation、把 `lastSeq/minAvailableSeq` 归零，并创建 `kind=full` pending operation。purge 不生成 tombstone，不删除 `sync_blobs` metadata 或文件；响应中的 `releasedBlobCandidates` 仅统计本次后不再被 projection 引用的 hash。

`GET /sync/manage/operations` 只返回当前用户 pending operations。普通自动同步和手动同步都必须先发现并持久化 pending operation、强制对应 scope reseed，reseed 完成后才 ACK。selective purge 不产生 tombstone，因此 reseed 必须在一个固定 `indexRevision` 下遍历所选分类的对象列表和详情，以该 current projection 为权威：不存在于 projection 且没有本地 pending mutation 的记录必须从本机删除；存在真实 pending upsert/delete 的记录保留本地值和原 mutation identity，稍后按用户编辑意图上传。完成原子投影替换后，本地 generation 更新为最新 generation、cursor 设置为该状态的 `minAvailableSeq`，再继续 `/sync/changes` 增量同步和上传。多个持久化 operation 以最新 generation 为完成条件，旧 operation 不得阻塞最新 generation；ACK 写使用当前最新 generation。ACK request ID 由 scope、operation ID 和当前 generation 确定性派生；仅支持 `operationAck` capability 时发送 `{"requestId":"...","expectedGeneration":N,"operationId":"..."}`，不支持时不得调用 ACK，operation 继续持久化等待能力恢复。purge 与 ACK 都使用 `(userId, requestId)` durable replay：相同 operation/body hash 返回精确原响应，不同 operation 或 body hash 返回 `replay_conflict` HTTP 409，该错误不属于设备签名拒绝。已存在 request replay 的精确重放或 `replay_conflict` 判定优先；对新 purge request，generation 不匹配必须优先于 `expectedIndexRevision` 不匹配返回 `generation_mismatch`。管理写在 per-user transaction lock 下执行，generation 与 `expectedIndexRevision` 的比较、删除、generation/revision 更新、operation 创建和 replay 持久化必须原子提交。

客户端 `/sync/changes` 请求不在每条 change JSON 中发送 `deviceId`；签名头中的设备 ID 是服务端审计来源，本地 Outbox 仍保留原设备审计数据。批次裁切、body hash、签名和实际发送必须共用同一个 canonical JSON byte encoder。Blob 下载必须按 status 广告的 `maxBlobBytes` 有界读取，并在安装任何文件或推进 cursor 前验证实际长度和 SHA-256。对象详情请求必须携带 `expectedIndexRevision`，并验证响应 revision 与请求完全一致。HTTP 409 `generation_mismatch`、`stale_cursor`、`future_cursor` 必须解析为类型化 cursor 冲突并严格校验携带的 generation/cursor metadata；同步可重新读取 status/reseed 后最多重试一次。固定 revision 索引读取遇到 `index_revision_conflict` 同样最多从新 status 重试一次，连续竞态必须向用户报错而不是无限循环。

### 5.2 Sync 固定测试向量

完整 canonical wire 示例见 [`fixtures/sync-v1.json`](fixtures/sync-v1.json)；后端镜像必须与该文件 byte-identical。

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
expectedGeneration: 1
```

```text
sync request message hex:
4c796e41492f76312f73796e632d72657175657374000001000000020001000200000002343200030000001073657373696f6e2d766563746f722d310004000000346b7a6476766a32756d6e64757961756633356f33366b366b773436326d756a7672613436746e337571677a6f766d69686f6367610005000000080000018bcfe5687b00060000002041414543417751464267634943516f4c4441304f4478415245684d5546525958000700000004504f535400080000000d2f73796e632f6368616e676573000900000020000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f000a000000080000000000000001

Ed25519 signature base64url:
-Q019gyA3ngLx2w19PfpFX7FqV6X04RJrECgf2x5NJMaKj5A4h_JOcqk3ga52-EPwZFsHJas15Osk8w4ygQ-Dg
```

### 5.3 Web 搜索

`POST /search/web` 使用账号 Bearer 鉴权，不使用设备同步签名。请求必须是严格 JSON object：`query` 必填且 trim 后长度为 1..1000；`provider` 可选且只允许 `auto`、`tavily`、`searxng`；`maxResults` 可选且范围 1..10；`language` 可选且为 BCP 47 风格 tag；`timeRange` 可选且只允许 `day`、`month`、`year`。客户端不得发送 upstream URL、origin、header、API key 或 token。响应返回实际 `provider` 和统一 `results`，每项包含 `title`、HTTP(S) `url`、`snippet`，以及可选 `score`、`publishedAt`。

客户端 `web_search` foundation tool 不公开 `provider` 或 `route` 参数。client/backend/auto 和客户端 Tavily/SearXNG 首选项是用户设置策略，由可信 composition 注入；模型和 Subagent 均不能覆盖。后端 `auto` 按服务端已配置 provider 顺序回退，显式 provider 不回退。未配置 provider 返回 503，上游失败、超时、无效或超大响应返回 502，响应和日志不得包含 upstream body、origin 或 secret。不存在旧 `/search`、snake_case 字段或客户端自定义 upstream 的兼容承诺。

## 6. 后续 LAN TLS 1.3 绑定

LAN 连接必须使用 TLS 1.3。配对记录绑定的是 TLS 证书 `SubjectPublicKeyInfo` DER 的 SHA-256：

```text
spkiPin = SHA-256(certificate.SubjectPublicKeyInfoDER)
```

TLS SPKI 必须由已登记的 Ed25519 device identity 对明确 domain-separated、包含 SPKI hash、设备 ID、有效期和上下文的 canonical 消息签名。验证方先验证 Ed25519 绑定，再按配对策略验证 TLS 1.3 连接和 SPKI。不得用长期 X25519 identity 替代该绑定，也不得把普通证书指纹当作 SPKI pin。

当前客户端 LAN 帧协议 v2 在 TLS 1.3 与双方 Ed25519 proof 认证后交换数据分类集合；分类包括对话、笔记、任务、日历、情景演绎、设置、模型配置、插件和静态资源。初次配对由发起方提出集合，响应方只能接受其子集；后续增加类别需要新的已认证提议，任一方减少类别时下一次同步取双方集合交集。变更 manifest 使用有界分页和精确逐页 ACK，并可在 change object 中 additive 地携带可选 `lineage` 字符串。新客户端仅将 lineage 与当前物理 dataset 一致的 LAN mutation 自动桥接到 cloud；缺失 lineage 的旧 peer 安全降级为不自动上传 cloud。该字段不会加入后端 `/sync/changes` wire。v1 不包含分类协商和分页结束字段，必须在 mDNS 发现或配对载荷校验阶段拒绝，不得进入同步会话或降级到无限制同步。该 JSON 帧 schema 仍属于客户端内部实现，跨实现固定向量和独立互操作规范后续补充。

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

## 10. Canonical Relay 与 Agent 工具轮次

本节记录客户端 `AgentLoopRuntime` 依赖的 `/relay/chat` wire 边界，不把 Agent 本机 run graph 暴露为后端协议。`runs`、`turns`、`items`、`tool_calls`、`snapshots` 和 MCP 配置均是客户端本机数据，不属于同步 table allowlist，也没有后端 Agent run API。

canonical chat message 支持 `system`、`user`、`assistant`、`tool`。assistant 可携带 `toolCalls`，每项必须有非空 `id`、`name` 和 JSON object `arguments`；tool message 必须携带匹配的 `toolCallId`。工具 schema 使用 `tools[].parameters` JSON object，`toolChoice` 只接受支持的字符串或指定名称对象。服务端严格拒绝未知顶层字段、尾随 JSON、非法角色和畸形 tool call。`extraParams` 是可选 JSON object，仅向 OpenAI-compatible 上游传递供应商扩展字段，且不得覆盖 relay 生成的 `model`、`messages`、`stream` 等核心字段；OpenAI 流式请求强制合并 `stream_options.include_usage=true`，保留该 object 中其他扩展成员。

非流式响应返回 assistant `content`、可选 `reasoning` 和 `toolCalls`。流式响应使用 SSE `event: chunk`；兼容字段为 `content`、`reasoning`、`toolCalls`、`finishReason`、`done`、`error`，新增元数据包括从 1 单调递增的 `sequence`、单流稳定 `responseId`、`type`、终止 `usage` 和结构化 `errorInfo`。`type` 按 `error`、`tool_calls`、`completed`、内容类型的顺序判定，所以携带工具调用的终止 delta 为 `type=tool_calls` 且同时 `done=true`；`done` 才是终止状态的权威字段。Anthropic `usage.inputTokens` 与 `totalTokens` 包含常规 input、cache creation input 和 cache read input。客户端严格拒绝 malformed SSE JSON、畸形 tool call、重复/空白 invocation ID 和 canonical `done=true` 前 EOF，不做 JSON fallback、call ID 合成或 malformed chunk 跳过。`StreamChunkAgentAdapter` 只把正文、思考、tool calls、完成和失败映射进 Agent runtime；`sequence`、`responseId`、`type` 和 `usage` 仍属于 relay 可观测元数据，不是本机 run identity 或 token budget 的权威输入。客户端 SSE diagnostics 只允许记录元数据，不得记录原始 data、正文、reasoning、arguments、call ID 或 error body。

每个 Agent turn 使用独立 `turnId`，但该 ID 不通过 relay wire 发送。客户端达到工具轮数上限后必须发起一次不暴露 tools 的强制最终 turn；若模型仍返回 tool calls，客户端不得执行，并以本机 `toolRoundLimitReached` 标记结束。取消是客户端控制语义：客户端停止等待模型或工具，并可忽略晚到结果；relay 不提供 durable Agent cancellation 或 run resume API。

## 11. MCP 协议边界

MCP 是客户端到用户配置 server 的独立协议，不经过 LynAI 后端，也不是本 v1 同步协议的扩展。当前客户端声明协议版本 `2025-06-18`，实现范围仅为 JSON-RPC 2.0 initialize/initialized、分页 `tools/list`、`tools/call`、`notifications/tools/list_changed` 和 `notifications/cancelled`。

远程 transport 是 Streamable HTTP，默认 HTTPS 且拒绝私网；用户可分别显式允许 HTTP 和私网。桌面 Linux/macOS/Windows 另支持逐行 JSON stdio。当前实现不支持 resources、prompts、sampling、roots、elicitation、OAuth discovery/flow、server-initiated request handling 或完整 capability negotiation，因此这些能力不得进入 LynAI wire compatibility 承诺。
