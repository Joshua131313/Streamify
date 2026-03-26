import { useMemo, useState } from "react";
import { Container } from "../../components/layout/Container/Container"
import GameCard from "../../components/ui/GameCard/GameCard";
import { PageHeader } from "../../components/ui/PageHeader/PageHeader";
import "./Sports.css"
import { Input } from "../../components/ui/Input/Input";
import { FaSearch, FaThLarge } from "react-icons/fa";
import { mapNBAToGameProps } from "../../utils/sports/nbaUtils";
import { useSports } from "../../context/SportsContext";
import { filterGames } from "../../utils/sports/sportsUtils";
import { mapNHLToGameProps } from "../../utils/sports/nhlUtils";
import { AppSwiper } from "../../components/ui/AppSwiper/AppSwiper";
import { SwiperSkeletonCard } from "../../components/ui/MediaCard/SkeletonCards/MediaSkeletonCard";
import { Button } from "../../components/ui/Button/Button";
import { useMultiWatch } from "../../context/MultiWatchContext";
import { sportStreams } from "../../data/sports/sportsData";
import { ChannelCard } from "../../components/ui/ChannelCard/ChannelCard";

export type QuickFilter = {
    label: string;
    value: string;
    type: "status" | "league" | "sport";
    default?: boolean;
};

export const quickFilters: QuickFilter[] = [
    // status
    { label: "Live", value: "LIVE", type: "status", default: true },
    { label: "Pre Game", value: "PRE", type: "status" },
    { label: "Upcoming", value: "FUT", type: "status", default: true },
    { label: "Finished", value: "FINAL", type: "status" },

    // league
    { label: "NBA", value: "NBA", type: "league", default: true, },
    { label: "NHL", value: "NHL", type: "league", default: true },

    // sport
    { label: "TV", value: "TV", type: "sport", default: true }
    // { label: "Basketball", value: "Basketball", type: "sport" },
    // { label: "Hockey", value: "Hockey", type: "sport" },
];

const Sports = () => {
    const { nbaGames, nbaGamesLoading, todaysNHLGames, nhlGamesLoading, search, setSearch } = useSports();
    const { adjustMultiWatchWindow, multiWatchWindowState } = useMultiWatch()
    const [filters, setFilters] = useState<QuickFilter[]>(quickFilters.filter(x=> x.default))
    const {  } = useMultiWatch();

    const nbaGameCards = useMemo(() => {
        return filterGames(
            nbaGames,
            search,
            filters
        );
    }, [nbaGames, search, filters]);

    const nhlGameCards = useMemo(() => {
        return filterGames(
            todaysNHLGames,
            search,
            filters
        );
    }, [todaysNHLGames, search, filters]);

    const handleClickFilter = (filter: QuickFilter) => {
        if (filters.some(x => x.value === filter.value)) {
            setFilters(prev => prev.filter(x => x.value !== filter.value));
        }
        else {
            setFilters(prev => [...prev, filter])
        }
    }

    const FilteredContainer = ({type, title, children} : {type: string, title: string, children: React.ReactNode}) => {
        return ( 
            filters.some(x => x.value === type) ? 
            <Container title={title}>
                {children}
            </Container>
            : null
        )
    }
 
    return (
        <div className="sports-page">
            <PageHeader
                title="Browse Sports"
                subTitle="Explore all live sports games"
                controls={
                    <>
                        <Input
                            placeholder="Search sports..."
                            Icon={FaSearch}
                            value={search}
                            onChange={(e) => setSearch(e.target.value)}
                        />
                        <Button onClick={() => adjustMultiWatchWindow(multiWatchWindowState.lastWindowState === "closed" ? "opened" : multiWatchWindowState.lastWindowState)}>
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
            <FilteredContainer type="TV" title="Sports Channels">
                <AppSwiper
                    isLoading={nbaGamesLoading}
                    items={sportStreams}
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
                    renderItem={(game) => (
                        <GameCard key={game.id} showSportName={false} game={game} />
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