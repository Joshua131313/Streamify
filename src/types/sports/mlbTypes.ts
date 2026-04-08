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

    venue?: string | null; 

    status: string;
    state?: "pre" | "in" | "post";

    clock?: string;

    period: MLBPeriod;

    inningDisplay?: string | null;

    homeTeam: MLBTeam;
    awayTeam: MLBTeam;

    broadcasts?: string[]; 

    gameLink?: string | null;
}