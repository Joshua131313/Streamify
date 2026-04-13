import { db, admin } from "../lib/firebase-admin";

export default async function handler(req, res) {
    const snapshot = await db.collection("gameNotifications").get();

    const now = Date.now();

    for (const doc of snapshot.docs) {
        const data = doc.data();

        if (data.notified) continue;

        const gameTime = new Date(data.startTime).getTime();

        // send notification within 1 min window
        if (gameTime <= now && gameTime > now - 60000) {
            await admin.messaging().sendEachForMulticast({
                tokens: data.tokens,
                notification: {
                    title: `${data.home} vs ${data.away}`,
                    body: "Game is starting now 🔥",
                },
            });

            await doc.ref.update({ notified: true });
        }
    }

    res.status(200).json({ success: true });
}