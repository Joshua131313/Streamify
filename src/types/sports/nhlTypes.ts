

import type { nhlTeamsMap } from "../../data/sports/nhlData";

export type NHLGameState = "pre" | "in" | "post";


export interface NHLPeriod {
  current: number;
  type: "REG" | "OT" | "SO";
  isHalftime: boolean;
}


export interface NHLTeam {
  id: string;
  name: string;
  abbreviation: keyof typeof nhlTeamsMap;
  logo: string;
  score: number;
}


export interface INHLGame {
  id: string;

  date: string;

  status: string; 
  state: NHLGameState;

  clock?: string;

  period: NHLPeriod;

  homeTeam: NHLTeam;
  awayTeam: NHLTeam;

  venue?: string | null;

  broadcasts?: string[];

  gameLink?: string | null;
}