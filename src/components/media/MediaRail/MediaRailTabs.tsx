import { getCategoryTabs, type TTab } from "../../../utils/categoryTabs"
import { useMediaRail } from "./MediaRailContext"
import "./MediaRail.css"
import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { StyledSelect } from "../../ui/StyledSelect/StyledSelect";

export const MediaRailTabs = () => {
    const { category, activeTab, setActiveTab } = useMediaRail();
    const tabs = getCategoryTabs(category);
    const containerRef = useRef<HTMLDivElement | null>(null);
    const tabRefs = useRef<(HTMLDivElement | null)[]>([]);
    const [indicator, setIndicator] = useState<{left: number, width: number}>({left: 0, width: 0});

    const updateIndicator = () => {
        const container = containerRef.current;
        const index = tabs.findIndex(t => t.value === (activeTab?.value ?? tabs[0].value));
        const activeEl = tabRefs.current[index];        
        if(!container || !activeEl) return;

        const cRect = container.getBoundingClientRect();
        const aRect = activeEl.getBoundingClientRect();

        setIndicator({
            left: aRect.left - cRect.left,
            width: aRect.width
        })
    }

    const tabsRow = tabs.map((tab, i) => {
        return (
            <div 
                key={tab.value}
                ref={(el) => {(tabRefs.current[i] = el)}}
                onClick={() => setActiveTab(tab)}
                className={`tab ${tab.value === activeTab?.value ? "active-tab" : ""}`}
            >
                {tab.label}
            </div>
        )
    })
    useEffect(() => {
        setActiveTab(tabs[0])
    }, [])
    useLayoutEffect(()=> {
        updateIndicator();
    }, [activeTab, tabs.length])

    useEffect(()=> {
        window.addEventListener("resize", updateIndicator);
        return () => window.removeEventListener("resize", updateIndicator)
    }, [activeTab])

    return (
        <>
        {tabsRow.length ?
            <div className="rail-tabs flex-row" ref={containerRef}>
                <div 
                    className="tab-indicator" 
                    style={{
                        width: `${indicator.width}px`,
                        transform: `translateX(${indicator.left}px)`
                    }}
                />
                {tabsRow}
            </div>
            : null
        }
        <StyledSelect<TTab, false> 
            options={tabs}
            value={activeTab}
            onChange={(t) => t && setActiveTab(t)}
            className="swiper-select"
        />
        </>
    )
}