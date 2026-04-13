import type { GameProps, Leagues } from "../../../types/sports/sportsTypes";

export interface SportCardsViewsProps {
    title: string;
    type?: Leagues | "TV" | "FOLLOW";
    games: GameProps[];
    gamesLoading: boolean;
}