package com.streamify.app.data

import com.google.firebase.Timestamp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FieldPath
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.Query
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.tasks.await
import java.util.Date

data class ChatMessage(val id: String, val message: String, val sender: String, val uid: String, val sentAt: Long, val reply: ChatReply? = null, val votes: Map<String, String> = emptyMap())
data class ChatReply(val id: String, val sender: String, val message: String)
val chatReactions = listOf("👍", "❤️", "😂", "🔥", "👏")
fun ChatMessage.handle() = sender.lowercase(java.util.Locale.ROOT).replace(Regex("[^a-z0-9_]"), "").take(24).ifBlank { "fan" } + "_" + uid.takeLast(4)
data class ChatState(val messages: List<ChatMessage> = emptyList(), val loading: Boolean = true, val error: String? = null)

class LiveChatRepository(private val auth: FirebaseAuth, private val db: FirebaseFirestore) {
    fun messages(room: String) = callbackFlow {
        require(room.isNotBlank() && '/' !in room)
        val listener = db.collection("live-chats").document(room).collection("messages")
            .orderBy("sentAt", Query.Direction.ASCENDING).limitToLast(100).addSnapshotListener { snapshot, error ->
                if (error != null) trySend(ChatState(loading = false, error = error.localizedMessage))
                else if (snapshot != null) trySend(ChatState(snapshot.documents.map { doc -> ChatMessage(doc.id,
                    (doc.get("message") as? String).orEmpty(), (doc.get("senderName") as? String)?.takeIf { it.isNotBlank() } ?: "Viewer",
                    (doc.get("senderId") as? String).orEmpty(), (doc.get("sentAt") as? Timestamp)?.toDate()?.time ?: 0L,
                    (doc.get("replyTo") as? Map<*, *>)?.let { ChatReply(it["id"] as? String ?: "", it["sender"] as? String ?: "Viewer", it["message"] as? String ?: "") },
                    (doc.get("reactionVotes") as? Map<*, *>)?.entries?.mapNotNull { (k,v) -> if (k is String && v is String && v in chatReactions) k to v else null }?.toMap().orEmpty()) }, loading = false))
            }
        awaitClose { listener.remove() }
    }
    suspend fun send(room: String, text: String, reply: ChatMessage? = null) {
        val message = text.trim()
        require(message.isNotEmpty() && message.length <= 1000) { "Use between 1 and 1,000 characters." }
        require(room.isNotBlank() && '/' !in room)
        val user = auth.currentUser ?: auth.signInAnonymously().await().user ?: error("Guest chat is unavailable. Please try again.")
        val chat = db.collection("live-chats").document(room)
        val entry = chat.collection("messages").document()
        db.runTransaction { tx ->
            val existing = tx.get(chat)
            check(auth.currentUser?.uid == user.uid) { "Account changed. Please try again." }
            if (!existing.exists()) tx.set(chat, mapOf("createdAt" to FieldValue.serverTimestamp(), "expiresAt" to Timestamp(Date(System.currentTimeMillis() + 12 * 60 * 60 * 1000))))
            tx.set(entry, mapOf("message" to message, "sentAt" to FieldValue.serverTimestamp(), "senderId" to user.uid,
                "senderName" to user.displayName?.takeIf { it.isNotBlank() }?.take(160).orEmpty().ifBlank { if (user.isAnonymous) "Guest ${user.uid.takeLast(4)}" else "Streamify viewer" }, "reactions" to emptyList<String>()) + (reply?.let { mapOf("replyTo" to mapOf("id" to it.id, "sender" to it.sender, "message" to it.message)) } ?: emptyMap()))
        }.await()
    }
    suspend fun react(room: String, messageId: String, emoji: String) {
        require(emoji in chatReactions && room.isNotBlank() && '/' !in room && messageId.isNotBlank() && '/' !in messageId)
        val user = auth.currentUser ?: auth.signInAnonymously().await().user ?: error("Guest chat is unavailable.")
        val ref = db.collection("live-chats").document(room).collection("messages").document(messageId)
        db.runTransaction { tx ->
            val snapshot = tx.get(ref)
            check(auth.currentUser?.uid == user.uid) { "Account changed. Please try again." }
            val previous = (snapshot.get("reactionVotes") as? Map<*, *>)?.get(user.uid)
            tx.update(ref, FieldPath.of("reactionVotes", user.uid), if (previous == emoji) FieldValue.delete() else emoji)
        }.await()
    }

}
