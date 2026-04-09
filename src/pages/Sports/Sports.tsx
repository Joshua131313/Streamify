import { Container } from "../../components/layout/Container/Container";
import GameCard from "../../components/ui/GameCard/GameCard";
import { PageHeader } from "../../components/ui/PageHeader/PageHeader";
import "./Sports.css";
import { Input } from "../../components/ui/Input/Input";
import { FaSearch, FaThLarge } from "react-icons/fa";
import { useSports, quickFilters, type SportFilterType } from "../../context/SportsContext";
import { AppSwiper } from "../../components/ui/AppSwiper/AppSwiper";
import { SwiperSkeletonCard } from "../../components/ui/MediaCard/SkeletonCards/MediaSkeletonCard";
import { Button } from "../../components/ui/Button/Button";
import { channelStreams } from "../../data/sports/sportsData";
import { ChannelCard } from "../../components/ui/ChannelCard/ChannelCard";
import { useWindow } from "../../hooks/utilHooks/useWindow";
import { SEO } from "../../components/SEO";
import SportsLayout from "./SportsLayout";
import { FilteredSportsContainer } from "../../components/layout/Container/FilteredSportsContainer";

const Sports = () => {
    const {
        nbaGamesLoading,
        nhlGamesLoading,
        mlbGamesLoading,
        nbaGameCards,
        nhlGameCards,
        mlbGameCards,
        favoriteGameCards
    } = useSports();

    return (
        <SportsLayout title="Sports" subTitle="Browse live sports" league="all" >
            {favoriteGameCards.length > 0 && (
                <Container title="Followed Teams">
                    <AppSwiper
                        items={favoriteGameCards}
                        itemKey={(item) => String(item.id ?? item.title)}
                        renderItem={(game) => (
                            <GameCard showSportName game={game} />
                        )}
                        skeleton={<SwiperSkeletonCard className="game-card-skeleton" />}
                    />
                </Container>
            )}

            <FilteredSportsContainer type="TV" title="Sports Channels">
                <AppSwiper
                    items={channelStreams}
                    itemKey={(item) => item.title}
                    renderItem={(stream) => (
                        <ChannelCard stream={stream} />
                    )}
                    skeleton={<SwiperSkeletonCard className="game-card-skeleton" />}
                />
            </FilteredSportsContainer>

            <FilteredSportsContainer type="NBA" title="NBA">
                <AppSwiper
                    isLoading={nbaGamesLoading}
                    items={nbaGameCards}
                    itemKey={(item) => String(item.id ?? item.title)}
                    renderItem={(game) => (
                        <GameCard showSportName={false} game={game} />
                    )}
                    skeleton={<SwiperSkeletonCard className="game-card-skeleton" />}
                />
            </FilteredSportsContainer>

            <FilteredSportsContainer type="NHL" title="NHL">
                <AppSwiper
                    isLoading={nhlGamesLoading}
                    items={nhlGameCards}
                    itemKey={(item) => String(item.id ?? item.title)}
                    renderItem={(game) => (
                        <GameCard showSportName={false} game={game} />
                    )}
                    skeleton={<SwiperSkeletonCard className="game-card-skeleton" />}
                />
            </FilteredSportsContainer>

            <FilteredSportsContainer type="MLB" title="MLB">
                <AppSwiper
                    isLoading={mlbGamesLoading}
                    items={mlbGameCards}
                    itemKey={(item) => String(item.id ?? item.title)}
                    renderItem={(game) => (
                        <GameCard showSportName={false} game={game} />
                    )}
                    skeleton={<SwiperSkeletonCard className="game-card-skeleton" />}
                />
            </FilteredSportsContainer>
        </SportsLayout>

    );
};

export default Sports;