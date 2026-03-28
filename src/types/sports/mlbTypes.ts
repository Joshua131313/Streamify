import type { mlbTeamsMap } from "../../data/sports/mlbData";

export interface MLBTeam {
    id: string;
    name: string;
    abbreviation: keyof typeof mlbTeamsMap;
    logo: string;

    score: number;

    record?: string;
}

export type MLBInningHalf = "top" | "bottom" | "mid" | "end" | null;

export interface MLBPeriod {
    current: number; // inning number
    type?: string;   // ESPN status type (optional)
    inningHalf: MLBInningHalf;
    isHalftime: boolean; // always false for MLB (kept for consistency)
}

export interface MLBBroadcast {
    market?: string;
    network: string;
}

export interface IMLBGame {
    id: string;

    date: string;

    venue?: string | null; // 🔥 matches backend (string, not object)

    status: string;
    state?: "pre" | "in" | "post";

    clock?: string;

    // 🔥 UPDATED (was inning → now period)
    period: MLBPeriod;

    // 🔥 UI-ready string
    inningDisplay?: string | null;

    homeTeam: MLBTeam;
    awayTeam: MLBTeam;

    broadcasts?: string[]; // 🔥 matches backend (array of strings now)

    gameLink?: string | null;
}