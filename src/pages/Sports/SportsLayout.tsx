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
import type { Leagues } from "../../types/sports/sportsTypes";

interface Props {
    title: string;
    subTitle: string;
    league: Leagues | "all";
    children: React.ReactNode;
}

const SportsLayout = (props: Props) => {
    const { title, subTitle, league } = props;
    const {
        search,
        setSearch,
        filters,
        addSportFilter,
    } = useSports();

    const { open } = useWindow("multiwatch");

    return (
        <div className="sports-page">
            <SEO title={title} description={subTitle} />

            <PageHeader
                title={title}
                subTitle={subTitle}
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
                            {quickFilters.filter(filter => {
                                // if all leagues, then show all leagues otherwise if specific league like nba dont show any
                                if(league === "all") return true;
                                return filter.type !== "league";
                            }).map(filter => (
                                <div
                                    key={filter.value}
                                    className={`${
                                        filters.some(f => f.value === filter.value)
                                            ? "active"
                                            : ""
                                    } quick-filter`}
                                    onClick={() => addSportFilter(filter)}
                                >
                                    {filter.label}
                                </div>
                            ))}
                        </div>
                    </>
                }
            />
          {props.children}
        </div>
    );
};

export default SportsLayout;