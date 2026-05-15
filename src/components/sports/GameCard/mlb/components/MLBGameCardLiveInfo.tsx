import { AppImg } from "../../../../ui/ImgProxy/AppImg";

import type {
    GameProps
} from "../../../../../types/sports/sportsTypes";

import type {
    IMLBGame
} from "../../../../../types/sports/mlbTypes";

import {
    mlbTeamsMap
} from "../../../../../data/sports/mlbData";

interface Props {
    game: IMLBGame;

    card: GameProps;
}

export const MLBGameCardLiveInfo = ({
    game,
    card
}: Props) => {

    const pitcher =
        game.live?.pitcher;

    const batter =
        game.live?.batter;

    const isTopInning =
        game.period?.inningHalf === "top";

    const isBottomInning =
        game.period?.inningHalf === "bottom";


    const awayColor =
        mlbTeamsMap[
            card.awayTeam.abbrev
        ]?.color ??
        "#2563eb";

    const homeColor =
        mlbTeamsMap[
            card.homeTeam.abbrev
        ]?.color ??
        "#dc2626";
    const batterColor =
        isTopInning
            ? awayColor
            : homeColor;

    const pitcherColor =
        isTopInning
            ? homeColor
            : awayColor;

    const pitcherName =
        pitcher?.shortName ??
        pitcher?.name ??
        "-";

    const batterName =
        batter?.shortName ??
        batter?.name ??
        "-";

    const pitchCount =
        game.live?.atBatPitchCount ??
        pitcher?.stats?.pitches ??
        "-";
    const batterSummary =
        batter?.summary ??
        "-";

    return (
        <div className="sport-live-info">

            <div className="sport-live-line pitcher">

                <span
                    className="sport-line-indicator"
                    style={{
                        backgroundColor:
                            pitcherColor
                    }}
                />

                <div className="sport-player-copy">

                    <div className="pitcher game-player">

                        {pitcher?.headshot && (
                            <AppImg
                                src={pitcher.headshot}
                            />
                        )}

                        <div className="pitcher-wrapper player-wrapper">

                            <span className="sport-player-role">
                                Pitcher
                            </span>

                            <span className="sport-player-name">
                                {pitcherName}
                            </span>

                        </div>

                    </div>

                </div>

                <span className="sport-player-stat">
                    P:{String(pitchCount)}
                </span>

            </div>

            <div className="sport-live-line batter">

                <span
                    className="sport-line-indicator"
                    style={{
                        backgroundColor:
                            batterColor
                    }}
                />

                <div className="sport-player-copy">

                    <div className="batter game-player">

                        {batter?.headshot && (
                            <AppImg
                                src={batter.headshot}
                            />
                        )}

                        <div className="batter-wrapper player-wrapper">

                            <span className="sport-player-role">
                                Batter
                            </span>

                            <span className="sport-player-name">
                                {batterName}
                            </span>

                        </div>

                    </div>

                </div>

                <span className="sport-player-stat">
                    {batterSummary}
                </span>

            </div>

        </div>
    );
};