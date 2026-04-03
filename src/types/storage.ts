export interface ShowHistory {
    showId: number;
    season: number;
    episode: number;
    updatedAt: Date;
}

export interface SearchMediaHistory {
    searchValue: string;
    timeStamp: Date;
}