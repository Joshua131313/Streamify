import { useState } from "react";
import { Window } from "./Window";
import {
    extractStreamInfoFromURL,
    getSportStream,
    getTeamLogo,
} from "../../../utils/sports/sportsUtils";
import "./Window.css";
import { StreamSelector } from "../StreamSelector/StreamSelector";
import type { SportStream } from "../../../types/sports/sportsTypes";
import { StreamPlayerPanel } from "../../sports/StreamPlayerPanel/StreamPlayerPanel";

interface Props {
    id: string;
}

export const PlayerWindow = (props: Props) => {
    const { id } = props;

    const { awayAbbrev, homeAbbrev, leagueName, provider } =
        extractStreamInfoFromURL(id);
        
    const MinimizedIcon = () => {
        return (
            <div className="player-window-icon app-icon">
                <img src={getTeamLogo(leagueName, homeAbbrev)} />
                <img src={getTeamLogo(leagueName, awayAbbrev)} />
            </div>
        );
    };


    return (
        <Window
            minimizedIcon={<MinimizedIcon />}
            id={id}
            title={`Watch ${homeAbbrev} vs ${awayAbbrev}`}
        >
            <div className="player-window">
                <StreamPlayerPanel
                    leagueName={leagueName}
                    homeAbbrev={homeAbbrev}
                    awayAbbrev={awayAbbrev}
                    provider={provider}
                />
            </div>
        </Window>
    );
};