import { db } from "../lib/firebase-admin";

export default async function handler(req, res) {
    try {
        if (req.method !== "POST") {
            return res.status(405).end();
        }

        const { token, gameId, home, away, startTime } = req.body;

        // 🔴 VALIDATION (IMPORTANT)
        if (!token || !gameId) {
            return res.status(400).json({ error: "Missing token or gameId" });
        }

        const ref = db.collection("gameNotifications").doc(gameId);

        const docSnap = await ref.get();

        if (docSnap.exists) {
            const data = docSnap.data();

            const existingTokens = data.tokens || [];

            await ref.update({
                tokens: [...new Set([...existingTokens, token])],
            });
        } else {
            await ref.set({
                tokens: [token],
                home,
                away,
                startTime,
                notified: false,
            });
        }

        return res.status(200).json({ success: true });

    } catch (err) {
        console.error("SUBSCRIBE GAME ERROR:", err);
        return res.status(500).json({ error: err.message });
    }
}