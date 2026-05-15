import type { Leagues } from "../../../types/sports/sportsTypes";
import type { SportDisplayGame } from "../../../types/sports/sportsDisplayTypes";

export type SportCardsViewType =
    | Leagues
    | "TV"
    | "FOLLOW";

export type SportCardsViewsProps = {
    title: string;
    type?: SportCardsViewType;
    games: SportDisplayGame[];
    gamesLoading: boolean;
};