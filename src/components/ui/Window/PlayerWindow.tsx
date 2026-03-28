import { useSearchParams } from "react-router-dom";
import { Window } from "./Window";
import { extractStreamInfoFromURL, getSportStream, getTeamLogo } from "../../../utils/sports/sportsUtils";
import type { Leagues, TeamAbbrevs, TStreamProvider } from "../../../types/sports/sportsTypes";
import "./Window.css"

interface Props {
    id: string;
}

export const PlayerWindow = (props: Props) => {
    const { id } = props;
    const { awayAbbrev, homeAbbrev, leagueName, provider } = extractStreamInfoFromURL(id);

    const MinimizedIcon = () => {
        return (
            <div className="player-window-icon app-icon">
                <img src={getTeamLogo(leagueName, homeAbbrev)} />
                <img src={getTeamLogo(leagueName, awayAbbrev)} />
            </div>
        )
    }

    return (
        <Window minimizedIcon={<MinimizedIcon />} id={id} title={`Watch ${homeAbbrev} vs ${awayAbbrev}`}>
            <div className="player-window">
                <iframe allowFullScreen src={
                    getSportStream(leagueName).find(x => x.provider === provider)?.buildStreamUrl({
                        awayTeamAbbrev: awayAbbrev,
                        homeTeamAbbrev: homeAbbrev
                    })
                }
                />
            </div>
        </Window>
    )
}