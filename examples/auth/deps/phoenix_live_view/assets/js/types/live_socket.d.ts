export function isUsedInput(el: any): any;
export default class LiveSocket {
    constructor(url: any, phxSocket: any, opts?: {});
    unloaded: boolean;
    socket: any;
    bindingPrefix: any;
    opts: {};
    params: any;
    viewLogger: any;
    metadataCallbacks: any;
    defaults: any;
    prevActive: Element;
    silenced: boolean;
    main: View;
    outgoingMainEl: any;
    clickStartedAtTarget: any;
    linkRef: number;
    roots: {};
    href: string;
    pendingLink: any;
    currentLocation: any;
    hooks: any;
    uploaders: any;
    loaderTimeout: any;
    disconnectedTimeout: any;
    /**
     * @type {ReturnType<typeof setTimeout> | null}
     */
    reloadWithJitterTimer: ReturnType<typeof setTimeout> | null;
    maxReloads: any;
    reloadJitterMin: any;
    reloadJitterMax: any;
    failsafeJitter: any;
    localStorage: any;
    sessionStorage: any;
    boundTopLevelEvents: boolean;
    boundEventNames: Set<any>;
    blockPhxChangeWhileComposing: any;
    serverCloseRef: any;
    domCallbacks: any;
    transitions: TransitionSet;
    currentHistoryPosition: number;
    version(): string;
    isProfileEnabled(): boolean;
    isDebugEnabled(): boolean;
    isDebugDisabled(): boolean;
    enableDebug(): void;
    enableProfiling(): void;
    disableDebug(): void;
    disableProfiling(): void;
    enableLatencySim(upperBoundMs: any): void;
    disableLatencySim(): void;
    getLatencySim(): number;
    getSocket(): any;
    connect(): void;
    disconnect(callback: any): void;
    replaceTransport(transport: any): void;
    execJS(el: any, encodedJS: any, eventType?: any): void;
    /**
     * Returns an object with methods to manipluate the DOM and execute JavaScript.
     * The applied changes integrate with server DOM patching.
     *
     * @returns {import("./js_commands").LiveSocketJSCommands}
     */
    js(): import("./js_commands").LiveSocketJSCommands;
    unload(): void;
    triggerDOM(kind: any, args: any): void;
    time(name: any, func: any): any;
    log(view: any, kind: any, msgCallback: any): void;
    requestDOMUpdate(callback: any): void;
    asyncTransition(promise: any): void;
    transition(time: any, onStart: any, onDone?: () => void): void;
    onChannel(channel: any, event: any, cb: any): void;
    reloadWithJitter(view: any, log: any): void;
    getHookDefinition(name: any): any;
    maybeInternalHook(name: any): any;
    maybeRuntimeHook(name: any): any;
    isUnloaded(): boolean;
    isConnected(): any;
    getBindingPrefix(): any;
    binding(kind: any): string;
    channel(topic: any, params: any): any;
    joinDeadView(): void;
    joinRootViews(): boolean;
    redirect(to: any, flash: any, reloadToken: any): void;
    replaceMain(href: any, flash: any, callback?: any, linkRef?: number): void;
    transitionRemoves(elements: any, callback: any): void;
    isPhxView(el: any): boolean;
    newRootView(el: any, flash: any, liveReferer: any): View;
    owner(childEl: any, callback: any): any;
    withinOwners(childEl: any, callback: any): void;
    getViewByEl(el: any): any;
    getRootById(id: any): any;
    destroyAllViews(): void;
    destroyViewByEl(el: any): void;
    getActiveElement(): Element;
    dropActiveElement(view: any): void;
    restorePreviouslyActiveFocus(): void;
    blurActiveElement(): void;
    /**
     * @param {{dead?: boolean}} [options={}]
     */
    bindTopLevelEvents({ dead }?: {
        dead?: boolean;
    }): void;
    eventMeta(eventName: any, e: any, targetEl: any): any;
    setPendingLink(href: any): number;
    resetReloadStatus(): void;
    commitPendingLink(linkRef: any): boolean;
    getHref(): string;
    hasPendingLink(): boolean;
    bind(events: any, callback: any): void;
    bindClicks(): void;
    bindClick(eventName: any, bindingName: any): void;
    dispatchClickAway(e: any, clickStartedAt: any): void;
    bindNav(): void;
    maybeScroll(scroll: any): void;
    dispatchEvent(event: any, payload?: {}): void;
    dispatchEvents(events: any): void;
    withPageLoading(info: any, callback: any): any;
    pushHistoryPatch(e: any, href: any, linkState: any, targetEl: any): void;
    historyPatch(href: any, linkState: any, linkRef?: number): void;
    historyRedirect(e: any, href: any, linkState: any, flash: any, targetEl: any): void;
    registerNewLocation(newLocation: any): boolean;
    bindForms(): void;
    debounce(el: any, event: any, eventType: any, callback: any): any;
    silenceEvents(callback: any): void;
    on(event: any, callback: any): void;
    jsQuerySelectorAll(sourceEl: any, query: any, defaultQuery: any): any;
}
import View from "./view";
declare class TransitionSet {
    transitions: Set<any>;
    promises: Set<any>;
    pendingOps: any[];
    reset(): void;
    after(callback: any): void;
    addTransition(time: any, onStart: any, onDone: any): void;
    addAsyncTransition(promise: any): void;
    pushPendingOp(op: any): void;
    size(): number;
    flushPendingOps(): void;
}
export {};
