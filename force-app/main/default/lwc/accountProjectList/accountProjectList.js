import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import PROJECT_OBJECT from '@salesforce/schema/Project__c';
import PROJECT_STATUS_FIELD from '@salesforce/schema/Project__c.Status__c';
import initProjectsCursor from '@salesforce/apex/AccountProjectListController.initProjectsCursor';
import fetchProjectsByCursor from '@salesforce/apex/AccountProjectListController.fetchProjectsByCursor';
import USER_LOCALE from '@salesforce/i18n/lang';
import USER_TIME_ZONE from '@salesforce/i18n/timeZone';

const PAGE_SIZE_OPTIONS = [
    { label: '5', value: '5' },
    { label: '10', value: '10' },
    { label: '25', value: '25' },
    { label: '50', value: '50' }
];

export default class AccountProjectList extends LightningElement {
    _recordId;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        if (value === this._recordId) {
            return;
        }
        this._recordId = value;
        if (this._recordId) {
            this.reloadProjectsFromStart();
        }
    }

    columns = [
        {
            label: '#',
            fieldName: 'rowNum',
            type: 'number',
            hideDefaultActions: true,
            cellAttributes: { alignment: 'left' }
        },
        {
            label: 'Name',
            fieldName: 'recordLink',
            type: 'url',
            typeAttributes: { label: { fieldName: 'name' }, target: '_blank' },
            hideDefaultActions: true
        },
        { label: 'Status', fieldName: 'status', hideDefaultActions: true },
        {
            label: 'Budget',
            fieldName: 'budget',
            type: 'currency',
            hideDefaultActions: true
        },
        {
            label: 'Created Date & Time',
            fieldName: 'createdDisplay',
            type: 'text',
            hideDefaultActions: true
        }
    ];

    //“All” plus Status__c values from uiObjectInfoApi
    statusOptions = [{ label: 'All statuses', value: 'All' }];
    // default RT id from getObjectInfo - required by getPicklistValues even if no custom RTs exists
    projectRecordTypeId;
    pageSizeOptions = PAGE_SIZE_OPTIONS;

    projects = [];
    totalMatchingCount = 0;
    pageIndex = 0;
    //Serialized Database.Cursor - recreated whenever filters / page size / account changes
    apexCursorJson;
    hasMore = false;//Whether another page exists after current rows

    selectedStatus = 'All';
    activeOnly = false;
    pageSize = 10;

    loadingProjects = false;

    @wire(getObjectInfo, { objectApiName: PROJECT_OBJECT })
    wiredProjectObjectInfo({ error, data }) {
        if (data?.defaultRecordTypeId) {
            this.projectRecordTypeId = data.defaultRecordTypeId;
        } else if (error) {
            this.projectRecordTypeId = undefined;
            this.notifyError('Unable to load Project object data', error);
        }
    }

    @wire(getPicklistValues, {
        recordTypeId: '$projectRecordTypeId',
        fieldApiName: PROJECT_STATUS_FIELD
    })
    wiredProjectStatusPicklist({ error, data }) {
        const allOpt = { label: 'All statuses', value: 'All' };

        if (data?.values?.length) {
            //console.log('data.values', data.values); 
            const dynamicOpts = data.values.map((entry) => ({
                label: entry.label,
                value: entry.value
            }));
            this.statusOptions = [allOpt, ...dynamicOpts];

            const allowed = new Set(this.statusOptions.map((o) => o.value));
            const prev = this.selectedStatus;
            if (!this.activeOnly && prev !== 'All' && !allowed.has(prev)) {
                this.selectedStatus = 'All';
                this.reloadProjectsFromStart();
            }
        } else if (data?.values?.length === 0) {
            this.statusOptions = [allOpt];
        } else if (error && this.projectRecordTypeId) {
            this.statusOptions = [allOpt];
            this.notifyError('Unable to load status picklist', error);
        }
    }

    handleAccountViewError(event) {
        const msg =
            event.detail?.message ||
            event.detail?.body?.message ||
            'Could not load account fields.';
        this.notifyError('Unable to load account', { body: { message: msg } });
    }

    get rangeLabel() {
        const total = this.totalMatchingCount;
        if (total === 0) {
            return 'No projects match your filters.';
        }
        const shown = this.projects.length;
        if (shown === 0) {
            return `No rows on this page (${total} matching filters).`;
        }
        const start = this.pageIndex * this.pageSize + 1;
        const end = Math.min(start + shown - 1, total);
        return `Showing ${start}–${end} of ${total} matching filters`;
    }

    get lastPageIndex() {
        const total = this.totalMatchingCount;
        if (total <= 0) {
            return 0;
        }
        return Math.ceil(total / this.pageSize) - 1;
    }

    get disableFirst() {
        return this.pageIndex <= 0 || this.loadingProjects;
    }

    get disablePrev() {
        return this.pageIndex <= 0 || this.loadingProjects;
    }

    get disableNext() {
        return !this.hasMore || this.loadingProjects;
    }

    get disableLast() {
        return (
            this.loadingProjects ||
            this.totalMatchingCount <= 0 ||
            this.pageIndex >= this.lastPageIndex
        );
    }

    get pageSizeValue() {
        return String(this.pageSize);
    }

    get statusDisabled() {
        return this.activeOnly === true;
    }

    handleStatusChange(event) {
        const value = event.detail.value;
        this.selectedStatus = value;
        //  choosing Active in the picklist toggles on as well.
        this.activeOnly = value === 'Active';
        this.reloadProjectsFromStart();
    }

    handleActiveToggle(event) {
        this.activeOnly = event.detail.checked;
        if (this.activeOnly) {
            this.selectedStatus = 'Active';
        } else {
            this.selectedStatus = 'All';
        }
        this.reloadProjectsFromStart();
    }

    handleRefresh() {
        this.selectedStatus = 'All';
        this.activeOnly = false;
        this.reloadProjectsFromStart();
    }

    handlePageSizeChange(event) {
        this.pageSize = Number(event.detail.value);
        this.reloadProjectsFromStart();
    }

    firstPage() {
        if (this.pageIndex <= 0) return;
        this.pageIndex = 0;
        this.fetchCurrentSlice();
    }

    prevPage() {
        if (this.pageIndex <= 0) return;
        this.pageIndex -= 1;
        this.fetchCurrentSlice();
    }

    nextPage() {
        if (!this.hasMore) return;
        this.pageIndex += 1;
        this.fetchCurrentSlice();
    }

    lastPage() {
        if (this.disableLast) return;
        this.pageIndex = this.lastPageIndex;
        this.fetchCurrentSlice();
    }

    reloadProjectsFromStart() {
        this.pageIndex = 0;
        this.apexCursorJson = null;
        this.projects = [];
        this.totalMatchingCount = 0;
        this.hasMore = false;
        this.initCursorAndLoadFirstSlice();
    }

    initCursorAndLoadFirstSlice() {
        if (!this.recordId) return;

        this.pageIndex = 0;

        this.loadingProjects = true;

        const statusArg = this.activeOnly ? 'Active' : this.selectedStatus;

        initProjectsCursor({
            accountId: this.recordId,
            statusFilter: statusArg,
            activeOnly: this.activeOnly
        })
            .then((init) => {
                this.apexCursorJson = init.apexCursor;
                this.totalMatchingCount =
                    typeof init.totalMatchingCount === 'number' ? init.totalMatchingCount : 0;
                this.normalizePageIndexForTotal();
                return this.fetchSliceInternal();
            })
            .catch((error) => {
                this.notifyError('Unable to load projects', error);
            })
            .finally(() => {
                this.loadingProjects = false;
            });
    }

    fetchCurrentSlice() {
        if (!this.recordId || !this.apexCursorJson) {
            this.pageIndex = 0;
            this.initCursorAndLoadFirstSlice();
            return;
        }

        this.normalizePageIndexForTotal();

        this.loadingProjects = true;
        this.fetchSliceInternal()
            .catch((error) => {
                this.notifyError('Unable to load projects', error);
            })
            .finally(() => {
                this.loadingProjects = false;
            });
    }

    normalizePageIndexForTotal() {
        const total = this.totalMatchingCount;
        if (total <= 0) {
            this.pageIndex = 0;
            return;
        }
        const maxPageIndex = Math.max(0, Math.ceil(total / this.pageSize) - 1);
        if (this.pageIndex > maxPageIndex) {
            this.pageIndex = maxPageIndex;
        }
    }

    fetchSliceInternal() {
        this.normalizePageIndexForTotal();

        const total = this.totalMatchingCount;
        let startIndex = this.pageIndex * this.pageSize;
        if (total > 0 && startIndex >= total) {
            this.pageIndex = 0;
            startIndex = 0;
        }

        return fetchProjectsByCursor({
            startIndex,
            pageSize: this.pageSize,
            apexCursor: this.apexCursorJson,
            totalRowCount: total
        }).then((rows) => {
            const rowOffset = this.pageIndex * this.pageSize;
            const mapped = (rows || []).map((row, idx) => ({
                ...row,
                rowNum: rowOffset + idx + 1,
                recordLink: `/lightning/r/Project__c/${row.id}/view`,
                createdDisplay: this.formatCreatedDateTime(row.createdDate)
            }));
            this.projects = mapped;

            const start = this.pageIndex * this.pageSize;
            const loadedThrough = start + mapped.length;
            this.hasMore = loadedThrough < this.totalMatchingCount;
        });
    }

    //Created Date & Time column- uses the current user’s Salesforce locale and time zone
    formatCreatedDateTime(value) {
        if (value == null || value === '') {
            return '';
        }
        try {
            const d = value instanceof Date ? value : new Date(value);
            if (Number.isNaN(d.getTime())) {
                return '';
            }
            return new Intl.DateTimeFormat(USER_LOCALE, {
                timeZone: USER_TIME_ZONE,
                dateStyle: 'medium',
                timeStyle: 'short'
            }).format(d);
        } catch (e) {
            return '';
        }
    }

    notifyError(title, error) {
        const message =
            error?.body?.message ||
            error?.message ||
            (typeof error === 'string' ? error : 'Unknown error');
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant: 'error',
                mode: 'sticky'
            })
        );
    }
}