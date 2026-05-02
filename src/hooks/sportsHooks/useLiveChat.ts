import { collection, onSnapshot, query, orderBy, serverTimestamp, addDoc, doc, getDoc, setDoc } from "firebase/firestore";
import { useEffect, useState } from "react";
import { auth, db } from "../../firebase/firebase";
import type { LiveChatMessage } from "../../types/sports/sportsTypes";
import { getOrCreateGuestUsername } from "../../utils/helpers";

interface Props {
    gameId: string;
}

interface LiveChat {
    messages: LiveChatMessage[];
    sendMessage: (message: string) => Promise<void>;
}

export const useLiveChat = ({ gameId }: Props): LiveChat => {
    const [liveChatMessages, setLiveChatMessages] = useState<LiveChatMessage[]>([]);
    const user = auth.currentUser;
    const generatedName = getOrCreateGuestUsername();

    useEffect(() => {
        console.log(",g",gameId)
        const q = query(
            collection(db, "live-chats", gameId, "messages"),
            orderBy("sentAt", "asc")
        );

        const unsubscribe = onSnapshot(q, (snapshot) => {
            const data = snapshot.docs.map(docSnap => ({
                firebaseId: docSnap.id,
                ...(docSnap.data() as LiveChatMessage),
            }));
            console.log("d", data)
            setLiveChatMessages(data);
        });

        return () => unsubscribe();
    }, [gameId]);

    const sendMessage = async (message: string) => {
        console.log("asd", message)
        if (!message.trim()) return;

        await addDoc(collection(db, "live-chats", gameId, "messages"), {
            message: message,
            sentAt: serverTimestamp(),
            senderId: user?.uid,
            senderName: !user?.isAnonymous ? user?.displayName : generatedName,
            reactions: [],
        });
    };
    const ensureChatExists = async () => {
        const chatRef = doc(db, "live-chats", gameId);
        const chatSnap = await getDoc(chatRef);

        if (!chatSnap.exists()) {
            await setDoc(chatRef, {
                createdAt: serverTimestamp(),
                expiresAt: new Date(Date.now() + 12 * 60 * 60 * 1000)
            });
        }
    };

    useEffect(() => {
        ensureChatExists()
    }, [gameId])

    return {
        messages: liveChatMessages,
        sendMessage
    };
};