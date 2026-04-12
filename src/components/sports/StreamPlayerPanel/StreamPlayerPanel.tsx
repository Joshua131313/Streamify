import { useState } from "react";
import { getSportStream } from "../../../utils/sports/sportsUtils";
import type { SportStream, Leagues, TeamAbbrevs } from "../../../types/sports/sportsTypes";
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

    const streams = getSportStream(leagueName);

    const defaultStream =
        streams.find((s) => s.provider === provider) ?? streams[0];

    const [activeStream, setActiveStream] = useState<SportStream | null>(
        defaultStream
    );

    const streamUrl = activeStream?.buildStreamUrl({
        awayTeamAbbrev: awayAbbrev,
        homeTeamAbbrev: homeAbbrev,
    });

    return (
        <div className="stream-player-panel">
            <iframe allowFullScreen src={streamUrl} />

            <StreamSelector
                streams={streams}
                value={activeStream}
                onChange={(stream) => setActiveStream(stream)}
            />
        </div>
    );
};