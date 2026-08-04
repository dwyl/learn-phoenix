export default Hooks;
declare namespace Hooks {
    namespace InfiniteScroll {
        function mounted(): void;
        function destroyed(): void;
        function throttle(interval: any, callback: any): (...args: any[]) => void;
    }
}
