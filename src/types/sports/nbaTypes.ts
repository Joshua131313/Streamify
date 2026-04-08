import type { nbaTeamsMap } from "../../data/sports/nbaData";

export type NBAGameStatus =
  | "SCHEDULED"
  | "PRE"
  | "LIVE"
  | "HALFTIME"
  | "FINAL";

export interface NBATeam {
  id: string;
  name: string;
  abbreviation: keyof typeof nbaTeamsMap;
  logo: string;

  score: number;

  record?: string;

  // optional stats later
  fouls?: number;
  timeouts?: number;
}

export interface NBAPeriod {
  current: number;        // quarter (1–4)
  type: "REG" | "OT";
  isHalftime: boolean;
}

export interface NBABroadcast {
  market: string;
  network: string;
}

export interface INBAGame {
  id: string;

  date: string;

  venue?: {
    name: string;
    city?: string;
    state?: string;
  };

  status: NBAGameStatus;
  clock?: string;

  homeTeam: NBATeam;
  awayTeam: NBATeam;

  period?: NBAPeriod;

  broadcasts?: NBABroadcast[];

  gameLink?: string;

}