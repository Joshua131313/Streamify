import { setGlobalOptions } from "firebase-functions";
import { onSchedule } from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";

admin.initializeApp();
const db = admin.firestore();

setGlobalOptions({ maxInstances: 10 });

export const cleanupFinishedGames = onSchedule(
  {
    schedule: "every 59 minutes",
    timeZone: "America/Montreal",
  },
  async () => {
    const now = admin.firestore.Timestamp.now();

    const chatsSnapshot = await db
      .collection("live-chats")
      .where("expiresAt", "<=", now)
      .get();

    if (chatsSnapshot.empty) {
      logger.info("No finished game chats");
      return;
    }

    for (const chatDoc of chatsSnapshot.docs) {
      logger.info(`Deleting finished game chat: ${chatDoc.id}`);

        await db.recursiveDelete(chatDoc.ref);
    }

    logger.info("Finished game cleanup done");
  }
);