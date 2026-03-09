import { createContext, useContext } from "react";

interface AuthContext {
    user: any;
}

const AuthContext = createContext<AuthContext | null>(null);

export const AuthProvider = ({ children } : {children: React.ReactNode}) => {
    const user = "";
    return (
        <AuthContext.Provider
            value={{
                user
            }}
        >
            {children}
        </AuthContext.Provider>
    )
}

export const useAuthProvider = () => {
    const ctx = useContext(AuthContext);
    if(!ctx) throw new Error("Auth must be used insides AuthProvier");
    return ctx;
}