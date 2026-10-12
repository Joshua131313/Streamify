import { useState } from "react";
import { useGameStreams } from "../../../hooks/sportsHooks/useGameStreams";
import type { Leagues, TeamAbbrevs } from "../../../types/sports/sportsTypes";
import { StreamSelector } from "../../ui/StreamSelector/StreamSelector";
import "./StreamPlayerPanel.css"

interface Props {
    leagueName: Leagues;
    homeAbbrev: TeamAbbrevs;
    awayAbbrev: TeamAbbrevs;
    provider?: string;
}

export const StreamPlayerPanel = (props: Props) => {
    const { leagueName, homeAbbrev, awayAbbrev, provider } = props;

    const { streams, isLoading, error } = useGameStreams(leagueName, homeAbbrev, awayAbbrev);

    const defaultStream =
        streams.find((s) => s.provider === provider) ?? streams[0];

    const [selectedProvider, setSelectedProvider] = useState<string | undefined>(provider);
    const activeStream = streams.find(s => s.provider === selectedProvider) ?? defaultStream ?? null;

    const streamUrl = activeStream?.buildStreamUrl({
        awayTeamAbbrev: awayAbbrev,
        homeTeamAbbrev: homeAbbrev,
    });

    return (
        <div className="stream-player-panel">
            {streamUrl ? <iframe title={`${leagueName} live stream`} allow="autoplay; fullscreen; picture-in-picture" allowFullScreen src={streamUrl} /> : (
                <div role="status">
                    <p>{isLoading ? "Finding live streams…" : error ? "Unable to load streams." : "No stream is available for this game yet."}</p>
                </div>
            )}

            <StreamSelector
                streams={streams}
                value={activeStream}
                onChange={(stream) => setSelectedProvider(stream?.provider)}
            />
        </div>
    );
};
