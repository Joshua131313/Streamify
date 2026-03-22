import { DateTime } from "luxon";
import type { GameStatus, TStreamProvider } from "../../types/sports/sportsTypes";
import type { INBAGame } from "../../types/sports/nbaTypes";
import type { GameProps } from "../../components/ui/GameCard/GameCard";


export const getNBAGameStatus = (date: string): GameStatus => {
    const gameTime = DateTime.fromISO(date, { zone: "America/Toronto" });
    const now = DateTime.now().setZone("America/Toronto");

    const diffInMinutes = now.diff(gameTime, "minutes").minutes;

    if (diffInMinutes < 0) {
        const minutesUntilStart = Math.abs(diffInMinutes);

        if (minutesUntilStart <= 30) {
            return "PRE";
        }

        return "FUT";
    }

    if (diffInMinutes <= 240) {
        return "LIVE";
    }

    return "FINAL";
};

export const mapStatus = (status: string, date: string): GameStatus => {
  if (status === "In Progress") return "LIVE";
  if (status === "Halftime") return "HALFTIME";
  if (status === "Final") return "FINAL";

  // Scheduled → decide PRE or FUT
  const gameTime = DateTime.fromISO(date);
  const now = DateTime.now();

  const diffMinutes = gameTime.diff(now, "minutes").minutes;

  if (diffMinutes <= 30 && diffMinutes > 0) {
    return "PRE";
  }

  return "FUT";
};

export const mapNBAToGameProps = (game: INBAGame): GameProps => {
  // safer title (use abbreviations if available)
  const title = `${game.awayTeam.abbreviation ?? game.awayTeam.name} vs ${
    game.homeTeam.abbreviation ?? game.homeTeam.name
  }`;

  return {
    id: game.id,

    title,
    startTime: game.startTimeUTC ?? game.date,

    // 🔥 use backend status (don’t recompute)
    status: mapStatus(game.status, game.date),

    homeTeam: {
      name: game.homeTeam.name,
      logo: game.homeTeam.logo,
      score: game.homeTeam.score, // ✅ include score
    },

    awayTeam: {
      name: game.awayTeam.name,
      logo: game.awayTeam.logo,
      score: game.awayTeam.score, // ✅ include score
    },

    // 🔥 real live info
    periodNumber: game.period?.type === "OT"
      ? "OT"
      : game.period?.current
      ? `Q${game.period.current}`
      : undefined,

    clock: game.clock ?? undefined,

    // 🎥 stream
    streamProvider: (game.streamProvider as TStreamProvider) ?? "sharkstreams",
    channel: game.channel ? String(game.channel) : "",

    sportName: "Basketball",
  };
};