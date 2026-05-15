import React from "react";

import {
    FaBaseballBall,
    FaTable,
} from "react-icons/fa";

import type {
    GameProps
} from "../../../../../types/sports/sportsTypes";

import type {
    IMLBGame
} from "../../../../../types/sports/mlbTypes";

import { GameCardTeam } from "../../GameCardTeam";

import { Icon } from "../../../../ui/Icon/Icon";

import { useGameCard } from "../../useGameCard";

import { useSports } from "../../../../../context/SportsContext";

import {
    getOrdinalSuffix
} from "../../../../../utils/sports/sportsUtils";

import { MLBGameCardCenter } from "./MLBGameCardCenter";

interface Props {
    game: IMLBGame;

    card: GameProps;

    showScoreboard: boolean;

    setShowScoreboard:
        React.Dispatch<
            React.SetStateAction<boolean>
        >;
}

export const MLBGameCardHeader = ({
    game,
    card,
    showScoreboard,
    setShowScoreboard
}: Props) => {

    const {
        leadingTeam
    } = useGameCard(card);

    const {
        layout
    } = useSports();

    const isPregame =
        game.state === "pre";

    const isFinal =
        game.state === "post" ||
        game.completed ||
        card.status === "FINAL";

    const isLive =
        !isPregame &&
        !isFinal;

    const inningHalf =
        game.period?.inningHalf;

    const inningNumber =
        game.period?.current;

    return (
        <section className="sport-card-top">

            <div className="sport-card-backdrop-logo away" />

            <div className="sport-card-backdrop-logo home" />

            <div className="sport-card-team-glow away" />

            <div className="sport-card-team-glow home" />

            <div className="sport-scoreboard-grid">

                <div className={`sport-team-column away`}>

                    <GameCardTeam
                        game={card}
                        leadingTeam={leadingTeam}
                        teamKey="awayTeam"
                    />

                    <div className="sport-team-abbrev">
                        {card.awayTeam.abbrev}
                    </div>

                </div>

                <MLBGameCardCenter
                    game={game}
                />

                <div className="sport-team-column home">

                    <GameCardTeam
                        game={card}
                        leadingTeam={leadingTeam}
                        teamKey="homeTeam"
                    />

                    <div className="sport-team-abbrev">
                        {card.homeTeam.abbrev}
                    </div>

                </div>

            </div>

            {(isLive && layout !== "list") && (
                <Icon
                    Icon={
                        showScoreboard
                            ? FaBaseballBall
                            : FaTable
                    }
                    className="sport-toggle-button"
                    onClick={() =>
                        setShowScoreboard(prev => !prev)
                    }
                />
            )}

        </section>
    );
};