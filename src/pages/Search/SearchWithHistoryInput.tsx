import { useEffect, useRef, useState } from "react";
import { FaSearch } from "react-icons/fa";
import { Input } from "../../components/ui/Input/Input";
import "./Search.css";
import type { SearchMediaHistory } from "../../types/storage";

type Props = {
    value: string;
    onChange: (value: string) => void;
    onSearch: (value: string) => void;
};

const HISTORY_KEY = "search-history";

export const SearchWithHistory = ({ value, onChange, onSearch }: Props) => {

    const [history, setHistory] = useState<SearchMediaHistory[]>([]);
    const [open, setOpen] = useState(false);
    const [highlighted, setHighlighted] = useState<number>(-1);

    const wrapperRef = useRef<HTMLDivElement>(null);

    useEffect(() => {
        const saved = localStorage.getItem(HISTORY_KEY);
        if (saved) {
            setHistory(JSON.parse(saved));
        }
    }, []);

    const saveHistory = (term: string) => {
        const trimmed = term.trim();
        if (!trimmed) return;

        const updated = [{searchValue: trimmed, timeStamp: new Date()}, ...history.filter(h => h.searchValue !== trimmed)].slice(0, 8);

        setHistory(updated);
        localStorage.setItem(HISTORY_KEY, JSON.stringify(updated));
    };

    const handleSearch = (term: string) => {
        const trimmed = term.trim();
        if (!trimmed) return;

        saveHistory(trimmed);
        onChange(trimmed);
        onSearch(trimmed);

        setOpen(false);
        setHighlighted(-1);
    };

    const filtered = history.filter(h =>
        h.searchValue.toLowerCase().includes(value.toLowerCase())
    );

    useEffect(() => {
        const handleClickOutside = (e: MouseEvent) => {
            if (!wrapperRef.current?.contains(e.target as Node)) {
                setOpen(false);
            }
        };

        document.addEventListener("mousedown", handleClickOutside);
        return () => document.removeEventListener("mousedown", handleClickOutside);

    }, []);

    const handleKeyDown = (e: React.KeyboardEvent) => {

        if (!open && (e.key === "ArrowDown" || e.key === "ArrowUp")) {
            setOpen(true);
            return;
        }

        if (e.key === "ArrowDown") {
            e.preventDefault();
            setHighlighted(prev =>
                prev < filtered.length - 1 ? prev + 1 : 0
            );
        }

        if (e.key === "ArrowUp") {
            e.preventDefault();
            setHighlighted(prev =>
                prev > 0 ? prev - 1 : filtered.length - 1
            );
        }

        if (e.key === "Enter") {
            if (highlighted >= 0) {
                handleSearch(filtered[highlighted].searchValue);
            } else {
                handleSearch(value);
            }
        }
    };

    return (
        <div className="search-history-wrapper" ref={wrapperRef}>

            <Input
                autoFocus
                Icon={FaSearch}
                placeholder="Type here to search"
                value={value}
                onFocus={() => setOpen(true)}
                onChange={(e) => {
                    onChange(e.target.value);
                    setOpen(true);
                    setHighlighted(-1);
                }}
                onKeyDown={handleKeyDown}
            />

            {open && filtered.length > 0 && (
                <div className="search-history-dropdown">

                    {filtered.map((item, index) => (
                        <div
                            key={item.searchValue}
                            className={`search-history-item ${highlighted === index ? "highlighted" : ""
                                }`}
                            onMouseDown={(e) => {
                                e.preventDefault();
                                handleSearch(item.searchValue);
                            }}
                        >
                            <FaSearch />
                            <span>{item.searchValue}</span>
                        </div>
                    ))}

                </div>
            )}

        </div>
    );
};