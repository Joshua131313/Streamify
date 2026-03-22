// =========================
// NHL API TYPES (ALL-IN-ONE)
// =========================

// -----------
// CORE TYPES
// -----------

export type NHLGameState = "FUT" | "PRE" | "LIVE" | "CRIT" | "OFF" | "FINAL";

export interface NHLTeamName {
    default: string;
    fr?: string;
}

export interface Odds {
    providerId: number;
    value: string;
}

export interface NHLTeam {
    id: number;
    commonName: NHLTeamName;
    placeName: NHLTeamName;
    placeNameWithPreposition: NHLTeamName;

    abbrev: string;

    logo: string;
    darkLogo: string;

    radioLink: string;

    score?: number;

    // optional depending on context
    awaySplitSquad?: boolean;
    homeSplitSquad?: boolean;
    odds?: Odds[];
}

export interface NHLBroadcast {
    id: number;
    market: string;
    countryCode: string;
    network: string;
    sequenceNumber: number;
}

export interface NHLVenue {
    default: string;
}

export interface NHLPeriodDescriptor {
    number: number;
    periodType: "REG" | "OT" | "SO";
    maxRegulationPeriods: number;
}

// -----------
// GAME
// -----------

export interface NHLGame {
    streamProvider: "embedsports";
    id: number;
    season: number;
    gameType: number;

    venue: NHLVenue;
    neutralSite: boolean;

    startTimeUTC: string;
    easternUTCOffset: string;
    venueUTCOffset: string;
    venueTimezone: string;

    gameState: NHLGameState;
    gameScheduleState: string;

    tvBroadcasts: NHLBroadcast[];

    awayTeam: NHLTeam;
    homeTeam: NHLTeam;

    periodDescriptor: NHLPeriodDescriptor;

    gameCenterLink: string;

    // optional
    ticketsLink?: string;
    ticketsLinkFr?: string;
}

// -----------
// DAY
// -----------

export interface GameDay {
    date: string;
    dayAbbrev: string;
    numberOfGames: number;
    datePromo: any[];
    games: NHLGame[];
}

// -----------
// RESPONSE
// -----------

export interface ScheduleResponse {
    nextStartDate: string;
    previousStartDate: string;
    gameWeek: GameDay[];
}

// =========================
// OPTIONAL HELPERS (🔥 USEFUL)
// =========================

export interface ParsedGame {
    away: NHLTeam;
    home: NHLTeam;
    embedUrl: string;
}

// Build embed link (matches your use case)

// Example fetch function
