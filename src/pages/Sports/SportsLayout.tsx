import { PageHeader } from "../../components/ui/PageHeader/PageHeader";
import "./Sports.css";
import { Input } from "../../components/ui/Input/Input";
import { FaGripHorizontal, FaLayerGroup, FaListAlt, FaRulerHorizontal, FaSearch, FaThLarge } from "react-icons/fa";
import { useSports, quickFilters, type SportFilterType, type SportsCardsLayout } from "../../context/SportsContext";
import { Button } from "../../components/ui/Button/Button";
import { useWindow } from "../../hooks/utilHooks/useWindow";
import { SEO } from "../../components/SEO";
import type { Leagues } from "../../types/sports/sportsTypes";
import { Container } from "../../components/layout/Container/Container";
import { FaList, FaX } from "react-icons/fa6";
import type { IconType } from "react-icons";
import { Icon } from "../../components/ui/Icon/Icon";
import { SportsSidebar } from "../../components/sports/SportsSidebar/SportsSidebar";

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
        setFilters,
        addSportFilter,
        layout,
        setLayout
    } = useSports();

    const { open, close, isOpen } = useWindow("multiwatch");

    const LayoutButton = ({ label, buttonLayout, Icon }: { label: string, buttonLayout: SportsCardsLayout, Icon: IconType }) => (
        <Button className={`${layout === buttonLayout ? "" : "secondary"}`} onClick={() => setLayout(buttonLayout)}>
            <Icon />
            {label}
        </Button>
    )

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
                        <Button
                            onClick={() => {
                                setSearch("");
                                setFilters([]);
                            }}
                        >
                            Clear Filters
                        </Button>
                        <div className="quick-filters">
                            {quickFilters.filter(filter => {
                                // if all leagues, then show all leagues otherwise if specific league like nba dont show any
                                if (league === "all") return true;
                                return filter.type !== "league";
                            }).map(filter => (
                                <div
                                    key={filter.value}
                                    className={`${filters.some(f => f.value === filter.value)
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
            <Container className="sports-ui-controllers">
                <Container styled className="inner-sports-ui-controllers">
                    <LayoutButton
                        Icon={FaGripHorizontal}
                        label="Slider View"
                        buttonLayout="slider"
                    />
                    <LayoutButton
                        Icon={FaThLarge}
                        label="Grid View"
                        buttonLayout="grid"
                    />
                    <LayoutButton
                        Icon={FaList}
                        label="List View"
                        buttonLayout="list"
                    />
                    <Button className={isOpen ? "" : "secondary"} onClick={() => isOpen ? close() : open()}>
                        <FaThLarge />
                        Multi-Watch
                    </Button>
                </Container>
            </Container>
            {props.children}
        </div>
    );
};

export default SportsLayout;