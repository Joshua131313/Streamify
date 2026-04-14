import React from "react";

import "./GameCard.css";
import type { GameProps } from "../../../types/sports/sportsTypes";

import { WatchButton } from "../Button/WatchButton";
import ExternalGameInfoButton from "../Button/ExternalGameInfoButton";
import { GameCardTeam } from "./GameCardTeam";
import { useGameCard } from "./useGameCard";

interface Props {
    game: GameProps;
    showSportName?: boolean;
    className?: string;
}

export const CompactGameCard: React.FC<Props> = ({
    game,
    showSportName,
    className = "",
}) => {
    const {
        openContextMenu,
        defaultSportStreamProvider,
        showPlayButtons,
        getGameStatusUI,
        leadingTeam
    } = useGameCard(game);

    const isLive = game.status === "LIVE" || game.status === "HALFTIME";
    const badgeClass = isLive ? "live-badge" : "not-started-badge";

    const badgeLabel = getGameStatusUI("compact").badgeLabel;
    const statusDetail = getGameStatusUI("compact").statusDetail;

    return (
        <div
            className={`${className} compact-game-card`}
            onContextMenu={openContextMenu}
        >
            <div className="inner-game-card">
                <div className="game-card-badges">
                    <div className={badgeClass}>{badgeLabel}</div>
                    {statusDetail && <div className="status-tag">{statusDetail}</div>}
                </div>

                <div className="logos">
                    <GameCardTeam game={game} leadingTeam={leadingTeam} teamKey="awayTeam" />
                    <GameCardTeam game={game} leadingTeam={leadingTeam} teamKey="homeTeam" />
                </div>
            </div>

            <div className={`game-card-buttons ${!showPlayButtons ? "single" : ""}`}>
                <ExternalGameInfoButton type="espn-small" url={game.gameLink} />
                {showPlayButtons && (
                    <WatchButton
                        variant="icon"
                        awayTeamAbbrev={game.awayTeam.abbrev}
                        homeTeamAbbrev={game.homeTeam.abbrev}
                        streamProvider={defaultSportStreamProvider}
                        league={game.leagueName}
                    />
                )}
            </div>
        </div>
    );
};

export default CompactGameCard;