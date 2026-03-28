// =========================
// NHL TYPES (ESPN NORMALIZED)
// =========================

import type { nhlTeamsMap } from "../../data/sports/nhlData";

// -----------
// STATUS
// -----------

export type NHLGameState = "pre" | "in" | "post";

// -----------
// PERIOD
// -----------

export interface NHLPeriod {
  current: number;
  type: "REG" | "OT" | "SO";
  isHalftime: boolean;
}

// -----------
// TEAM
// -----------

export interface NHLTeam {
  id: string;
  name: string;
  abbreviation: keyof typeof nhlTeamsMap;
  logo: string;
  score: number;
}

// -----------
// GAME (🔥 MAIN TYPE)
// -----------

export interface INHLGame {
  id: string;

  date: string;

  status: string; // "In Progress", etc.
  state: NHLGameState;

  clock?: string;

  period: NHLPeriod;

  homeTeam: NHLTeam;
  awayTeam: NHLTeam;

  venue?: string | null;

  broadcasts?: string[];

  gameLink?: string | null;
}