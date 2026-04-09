import { useMemo, useState } from "react";
import { Container } from "../../components/layout/Container/Container"
import GameCard from "../../components/ui/GameCard/GameCard";
import { PageHeader } from "../../components/ui/PageHeader/PageHeader";
import "./Sports.css"
import { Input } from "../../components/ui/Input/Input";
import { FaSearch, FaThLarge } from "react-icons/fa";
import { useSports } from "../../context/SportsContext";
import { filterGames } from "../../utils/sports/sportsUtils";
import { AppSwiper } from "../../components/ui/AppSwiper/AppSwiper";
import { SwiperSkeletonCard } from "../../components/ui/MediaCard/SkeletonCards/MediaSkeletonCard";
import { Button } from "../../components/ui/Button/Button";
import { channelStreams } from "../../data/sports/sportsData";
import { ChannelCard } from "../../components/ui/ChannelCard/ChannelCard";
import { useWindow } from "../../hooks/utilHooks/useWindow";
import { SEO } from "../../components/SEO";
import { navLinks } from "../../components/Navbar/Navbar";
import { AppNavLink } from "../../components/Navbar/AppNavLink";
import { useFavoriteTeamsContext } from "../../context/FavoriteTeamsContext";

export type QuickFilter = {
    label: string;
    value: string;
    type: "status" | "league" | "sport";
};

export const quickFilters: QuickFilter[] = [
    // status
    { label: "Live", value: "LIVE", type: "status" },
    { label: "Pre Game", value: "PRE", type: "status" },
    { label: "Upcoming", value: "FUT", type: "status" },
    { label: "Finished", value: "FINAL", type: "status" },

    // league
    { label: "NBA", value: "NBA", type: "league" },
    { label: "NHL", value: "NHL", type: "league" },
    { label: "MLB", value: "MLB", type: "league", },

    // sport
    { label: "TV", value: "TV", type: "league" }
    // { label: "Basketball", value: "Basketball", type: "sport" },
    // { label: "Hockey", value: "Hockey", type: "sport" },
];

const Sports = () => {
    const {
        nbaGames,
        nbaGamesLoading,
        nhlGames,
        nhlGamesLoading,
        mlbGames,
        mlbGamesLoading,
        search,
        setSearch
    } = useSports();
    const [filters, setFilters] = useState<QuickFilter[]>([])
    const { favoriteTeams } = useFavoriteTeamsContext();
    const { open } = useWindow("multiwatch");

    const nbaGameCards = useMemo(() => {
        return filterGames(
            nbaGames,
            search,
            filters
        );
    }, [nbaGames, search, filters]);
    const mlbGameCards = useMemo(() => {
        return filterGames(
            mlbGames,
            search,
            filters
        );
    }, [mlbGames, search, filters]);
    const nhlGameCards = useMemo(() => {
        return filterGames(
            nhlGames,
            search,
            filters
        );
    }, [nhlGames, search, filters]);

    const favoriteGames = useMemo(() => {
        if (!favoriteTeams.length) return [];

        const favSet = new Set(favoriteTeams.map(t => t.abbrev));

        const allGames = [
            ...nbaGameCards,
            ...nhlGameCards,
            ...mlbGameCards,
        ];

        return allGames.filter(game =>
            favSet.has(game.awayTeam.abbrev) ||
            favSet.has(game.homeTeam.abbrev)
        );
    }, [favoriteTeams, nbaGameCards, nhlGameCards, mlbGameCards]);

    const handleClickFilter = (filter: QuickFilter) => {
        if (filters.some(x => x.value === filter.value)) {
            setFilters(prev => prev.filter(x => x.value !== filter.value));
        }
        else {
            setFilters(prev => [...prev, filter])
        }
    }

    const FilteredContainer = ({ type, title, children }: { type: string, title: string, children: React.ReactNode }) => {
        return (
            (!(filters.filter(f => f.type === "league").length > 0) || filters.some(x => x.value === type)) ?
                <Container title={title}>
                    {children}
                </Container>
                : null
        )
    }

    return (
        <div className="sports-page">
            <SEO
                title="Sports"
                description="Explore all live sports"
            />
            <PageHeader
                title="Browse Sports"
                subTitle="Explore all live sports games"
                controls={
                    <>
                        <Input
                            placeholder="Filter games..."
                            Icon={FaSearch}
                            value={search}
                            onChange={(e) => setSearch(e.target.value)}
                        />
                        <Button onClick={() => open()}>
                            <FaThLarge />
                            Multi-Watch
                        </Button>
                        <div className="quick-filters">
                            {quickFilters.map(filter => (
                                <div className={`${filters.some(x => x.value === filter.value) ? "active" : ""} quick-filter`} onClick={() => handleClickFilter(filter)}>
                                    {filter.label}
                                </div>
                            ))}
                        </div>
                    </>
                }
            />
            {
                favoriteGames.length > 0 &&
                <Container title="Favorite Teams">
                    <AppSwiper
                        items={favoriteGames}
                        itemKey={(item) => String(item.id ?? item.title)}
                        renderItem={(game) => (
                            <GameCard showSportName={false} game={game} />
                        )}
                        skeleton={<SwiperSkeletonCard className="game-card-skeleton" />}
                    />
                </Container>
            }
            <FilteredContainer type="TV" title="Sports Channels">
                <AppSwiper
                    items={channelStreams}
                    itemKey={(item) => item.title}
                    renderItem={(stream) => (
                        <ChannelCard stream={stream} key={stream.provider} />
                    )}
                    skeleton={<SwiperSkeletonCard className="game-card-skeleton" />}
                />
            </FilteredContainer>
            <FilteredContainer type="NBA" title="NBA">
                <AppSwiper
                    isLoading={nbaGamesLoading}
                    items={nbaGameCards}
                    itemKey={(item) => String(item.id ?? item.title)}
                    renderItem={(game) => (
                        <GameCard showSportName={false} game={game} />
                    )}
                    skeleton={<SwiperSkeletonCard className="game-card-skeleton" />}
                />
            </FilteredContainer>

            <FilteredContainer type="NHL" title="NHL">
                {/* {nhlGameCards.map((game, index) => (
                    <GameCard showSportName={false} key={index} game={(game)} />
                ))} */}
                <AppSwiper
                    isLoading={nhlGamesLoading}
                    items={nhlGameCards}
                    itemKey={(item) => String(item.id ?? item.title)}
                    renderItem={(game) => (
                        <GameCard key={game.id} showSportName={false} game={game} />
                    )}
                    skeleton={<SwiperSkeletonCard className="game-card-skeleton" />}
                />
            </FilteredContainer>
            <FilteredContainer type="MLB" title="MLB">
                <AppSwiper
                    isLoading={mlbGamesLoading}
                    items={mlbGameCards}
                    itemKey={(item) => String(item.id ?? item.title)}
                    renderItem={(game) => (
                        <GameCard key={game.id} showSportName={false} game={game} />
                    )}
                    skeleton={<SwiperSkeletonCard className="game-card-skeleton" />}
                />
            </FilteredContainer>

        </div>
    )
}
export default Sports;