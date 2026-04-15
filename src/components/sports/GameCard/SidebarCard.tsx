import type { GameProps, GameTeam, Leagues, TeamInfo } from "../../../types/sports/sportsTypes";
import { getDefaultStreamProvider, getTeamLogo } from "../../../utils/sports/sportsUtils";
import { FollowButton } from "../../ui/Button/FollowButton";
import { WatchButton } from "../../ui/Button/WatchButton";
import { AppImg } from "../../ui/ImgProxy/AppImg";
import { useGameCard } from "./useGameCard";
import "./GameCard.css"
import React from "react";

interface Props {
    team: GameTeam;
    game?: GameProps;
}

export const SidebarCard = React.memo((props: Props) => {
    const { team, game } = props;

    return (
        <div className="sidebar-card">
            <div className="team-logo-name">
                <AppImg src={getTeamLogo(team.league, team.abbrev)} />
                <span>{team.name}</span>
            </div>
            <div className="sidebar-card-controls">
                <FollowButton
                    team={team}
                    variant="icon"
                />
                {
                    game &&
                    <WatchButton
                        streamProvider={getDefaultStreamProvider(game?.leagueName)}
                        awayTeamAbbrev={game.awayTeam.abbrev}
                        homeTeamAbbrev={game.homeTeam.abbrev}
                        league={game.leagueName}
                    />
                }
            </div>
        </div>
    )
})