import { useQuery } from "@tanstack/react-query";
import type { Leagues, SportStream, TeamAbbrevs } from "../../types/sports/sportsTypes";
import { getTeamsMapFromLeague } from "../../utils/sports/sportsUtils";
import { findStreamMatch, type StreamMatch } from "../../utils/sports/streamMatch";

const API = "https://streamed.pk/api";

async function fetchArray<T>(path: string, signal: AbortSignal): Promise<T[]> {
    const response = await fetch(`${API}${path}`, { signal: AbortSignal.any([signal, AbortSignal.timeout(12000)]) });
    if (!response.ok) throw new Error("The sports stream service is unavailable.");
    const data: unknown = await response.json();
    if (!Array.isArray(data)) throw new Error("Invalid sports stream response.");
    return data as T[];
}

interface LiveStream { embedUrl: string; streamNo: number; language: string; hd: boolean }

export function useGameStreams(league: Leagues | null, home: TeamAbbrevs, away: TeamAbbrevs) {
    const matches = useQuery({
        queryKey: ["sports-stream-matches"],
        queryFn: ({ signal }) => fetchArray<StreamMatch>("/matches/all", signal),
        enabled: !!league,
        staleTime: 30000,
        refetchInterval: 60000,
    });
    const teams = league ? getTeamsMapFromLeague(league) : {};
    const category = league === "NHL" ? "hockey" : league === "MLB" ? "baseball" : "basketball";
    const match = findStreamMatch(matches.data ?? [], category, teams[home]?.teamName ?? "", teams[away]?.teamName ?? "");
    const sources = match?.sources ?? [];
    const streams = useQuery({
        queryKey: ["sports-game-streams", league, home, away, match?.id, JSON.stringify(sources)],
        enabled: !!match,
        queryFn: async ({ signal }): Promise<SportStream[]> => {
            const results = await Promise.allSettled(sources.map(async source => {
                const data = await fetchArray<LiveStream>(`/stream/${encodeURIComponent(source.source)}/${encodeURIComponent(source.id)}`, signal);
                return data.filter(stream => {
                    try { return new URL(stream.embedUrl).protocol === "https:"; } catch { return false; }
                }).map(stream => ({
                    provider: `streamed-${source.source}-${stream.streamNo}` as const,
                    label: `${source.source} ${stream.streamNo} · ${stream.language || "Unknown"}${stream.hd ? " · HD" : ""}`,
                    buildStreamUrl: () => stream.embedUrl,
                }));
            }));
            if (results.every(result => result.status === "rejected")) throw new Error("Unable to load stream sources. Please retry.");
            return results.flatMap(result => result.status === "fulfilled" ? result.value : []);
        },
        staleTime: 30000,
        refetchInterval: 60000,
    });
    return {
        streams: streams.data ?? [],
        isLoading: !!league && (matches.isPending || (!!match && streams.isPending)),
        error: matches.error ?? (match ? streams.error : null),
        retry: () => { void matches.refetch(); if (match) void streams.refetch(); },
    };
}
