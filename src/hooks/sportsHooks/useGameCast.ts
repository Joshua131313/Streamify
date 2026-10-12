import { useMemo } from "react";
import type { SportDisplayGame } from "../../types/sports/sportsDisplayTypes";

export const useGameCast = (
    game: SportDisplayGame
) => {

    return useMemo(() => {

        const raw = game.raw;

        const isPregame =
            raw.state === "pre";

        const isFinal =
            raw.state === "post" ||
            game.card.status === "FINAL";

        const isLive =
            !isPregame &&
            !isFinal;

        return {
            raw,
            card: game.card,

            league: game.league,

            isPregame,
            isFinal,
            isLive,
        };

    }, [game]);
};