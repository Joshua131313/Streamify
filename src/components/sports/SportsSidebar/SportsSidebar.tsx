import { useState } from "react";
import { useSports } from "../../../context/SportsContext";
import { mlbTeamsMap } from "../../../data/sports/mlbData";
import { nbaTeamsMap } from "../../../data/sports/nbaData";
import { nhlTeamsMap } from "../../../data/sports/nhlData";
import { getLeagueFromTeam, getTeamLogo } from "../../../utils/sports/sportsUtils";
import { SearchableContainer } from "../../layout/Container/SearchableContainer";
import { SidebarCard } from "../GameCard/SidebarCard";
import "./SportsSidebar.css"
import { FaChevronLeft, FaChevronRight } from "react-icons/fa";

export const SportsSidebar = () => {
    const [show, setShow] = useState(false);
    const { liveGames, followedTeams } = useSports();
    const renderedGameIds = new Set<string>();

    return (
        <>
        {show && 
        <div className="sports-sidebar">
            <SearchableContainer
                title="Teams Playing Now"
                data={liveGames}
                defaultOpened
                searchFn={(game, search) =>
                    game.homeTeam.name.toLowerCase().includes(search) ||
                    game.awayTeam.name.toLowerCase().includes(search)
                }
                renderItem={(game) => (
                    <div className="game-group" key={game.id}>
                        <SidebarCard team={game.awayTeam} game={game} />
                        <SidebarCard team={game.homeTeam} game={game} />
                    </div>
                )}
            />
            <SearchableContainer
                title="Followed Teams"
                data={followedTeams}
                defaultOpened
                searchFn={(team, search) =>
                    team.name.toLowerCase().includes(search) ||
                    team.abbrev.toLowerCase().includes(search)
                }
                renderItem={(team) => {
                    const game = liveGames.find(g =>
                        g.homeTeam.abbrev === team.abbrev ||
                        g.awayTeam.abbrev === team.abbrev
                    );

                    if (!game) {
                        return (
                            <SidebarCard
                                key={team.abbrev}
                                team={team}
                            />
                        );
                    }

                    const isHome = game.homeTeam.abbrev === team.abbrev;
                    const opponent = isHome ? game.awayTeam : game.homeTeam;

                    const isOpponentFollowed = followedTeams.some(
                        t => t.abbrev === opponent.abbrev
                    );

                    if (isOpponentFollowed) {
                        if (renderedGameIds.has(String(game.id))) return null;

                        renderedGameIds.add(String(game.id));

                        return (
                            <div className="game-group" key={game.id}>
                                <SidebarCard team={game.awayTeam} game={game} />
                                <SidebarCard team={game.homeTeam} game={game} />
                            </div>
                        );
                    }

                    return (
                        <SidebarCard
                            key={team.abbrev}
                            team={team}
                            game={game}
                        />
                    );
                }}
            />
            <SearchableContainer
                title="NBA Teams"
                data={Object.values(nbaTeamsMap)}
                searchFn={(team, search) =>
                    team.teamName.toLowerCase().includes(search) ||
                    team.abbreviation.toLowerCase().includes(search)
                }
                renderItem={(team) => (
                    <SidebarCard
                        key={team.abbreviation}
                        team={{
                            abbrev: team.abbreviation,
                            logo: getTeamLogo("NBA", team.abbreviation),
                            name: team.teamName,
                            league: team.league
                        }}
                    />
                )}
            />
            <SearchableContainer
                title="NHL Teams"
                data={Object.values(nhlTeamsMap)}
                searchFn={(team, search) =>
                    team.teamName.toLowerCase().includes(search) ||
                    team.abbreviation.toLowerCase().includes(search)
                }
                renderItem={(team) => (
                    <SidebarCard
                        key={team.abbreviation}
                        team={{
                            abbrev: team.abbreviation,
                            logo: getTeamLogo("NHL", team.abbreviation),
                            name: team.teamName,
                            league: team.league
                        }}
                    />
                )}
            />
            <SearchableContainer
                title="MLB Teams"
                data={Object.values(mlbTeamsMap)}
                searchFn={(team, search) =>
                    team.teamName.toLowerCase().includes(search) ||
                    team.abbreviation.toLowerCase().includes(search)
                }
                renderItem={(team) => (
                    <SidebarCard
                        key={team.abbreviation}
                        team={{
                            abbrev: team.abbreviation,
                            logo: getTeamLogo("MLB", team.abbreviation),
                            name: team.teamName,
                            league: team.league
                        }}
                    />
                )}
            />
        </div>
        }
        <div className={`${show ? "active" : ""} sports-sidebar-controller`} onClick={() => setShow(!show)}>
           {show ? <FaChevronLeft /> : <FaChevronRight />}
        </div>
        </>
    );
};