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

export const HorizontalGameCard: React.FC<Props> = ({
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

    const badgeLabel = getGameStatusUI("full").badgeLabel;
    const statusDetail = getGameStatusUI("full").statusDetail;

    return (
        <div
            className={`${className} game-card-horizontal`}
            onContextMenu={openContextMenu}
        >
            <div className="game-card-horizontal-matchup">
                <div className="horizontal-team-row">
                    <GameCardTeam leadingTeam={leadingTeam} showTeamName showFollowButton game={game} teamKey="awayTeam" />
                    <div className="game-card-badges horizontal-badges">
                        <div className={badgeClass}>{badgeLabel}</div>
                        {statusDetail && <div className="status-tag">{statusDetail}</div>}
                    </div>
                </div>
                <div className="horizontal-team-row">
                    <GameCardTeam leadingTeam={leadingTeam} showTeamName showFollowButton game={game} teamKey="homeTeam" />
                    <div className={`game-card-buttons horizontal-buttons ${!showPlayButtons ? "single" : ""}`}>
                        <ExternalGameInfoButton url={game.gameLink} />
                        {showPlayButtons && (
                            <WatchButton
                                variant="button"
                                awayTeamAbbrev={game.awayTeam.abbrev}
                                homeTeamAbbrev={game.homeTeam.abbrev}
                                streamProvider={defaultSportStreamProvider}
                                league={game.leagueName}
                            />
                        )}
                    </div>
                </div>
            </div>
        </div>
    );
};

export default HorizontalGameCard;