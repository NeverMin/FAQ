# --
# Kernel/Modules/AgentFAQSearchSmall.pm - module for FAQ search
# Copyright (C) 2001-2013 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Modules::AgentFAQSearchSmall;

use strict;
use warnings;

use Kernel::System::FAQ;
use Kernel::System::SearchProfile;
use Kernel::System::Valid;
use Kernel::System::VariableCheck qw(:all);

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    # check needed objects
    for my $Object (
        qw(ParamObject DBObject LayoutObject LogObject UserObject GroupObject ConfigObject MainObject EncodeObject)
        )
    {
        if ( !$Self->{$Object} ) {
            $Self->{LayoutObject}->FatalError( Message => "Got no $Object!" );
        }
    }

    # create additional objects
    $Self->{FAQObject}           = Kernel::System::FAQ->new(%Param);
    $Self->{SearchProfileObject} = Kernel::System::SearchProfile->new(%Param);
    $Self->{ValidObject}         = Kernel::System::Valid->new(%Param);

    # get config for frontend
    $Self->{Config} = $Self->{ConfigObject}->Get("FAQ::Frontend::AgentFAQSearch");

    # set default interface settings
    $Self->{Interface} = $Self->{FAQObject}->StateTypeGet(
        Name   => 'internal',
        UserID => $Self->{UserID},
    );
    $Self->{InterfaceStates} = $Self->{FAQObject}->StateTypeList(
        Types  => $Self->{ConfigObject}->Get('FAQ::Agent::StateTypes'),
        UserID => $Self->{UserID},
    );

    $Self->{MultiLanguage} = $Self->{ConfigObject}->Get('FAQ::MultiLanguage');

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $Output;

    # get config data
    $Self->{StartHit} = int( $Self->{ParamObject}->GetParam( Param => 'StartHit' ) || 1 );
    $Self->{SearchLimit} = $Self->{Config}->{SearchLimit} || 500;
    $Self->{SortBy} = $Self->{ParamObject}->GetParam( Param => 'SortBy' )
        || $Self->{Config}->{'SortBy::Default'}
        || 'FAQID';
    $Self->{OrderBy} = $Self->{ParamObject}->GetParam( Param => 'OrderBy' )
        || $Self->{Config}->{'Order::Default'}
        || 'Down';
    $Self->{Profile}        = $Self->{ParamObject}->GetParam( Param => 'Profile' )        || '';
    $Self->{SaveProfile}    = $Self->{ParamObject}->GetParam( Param => 'SaveProfile' )    || '';
    $Self->{TakeLastSearch} = $Self->{ParamObject}->GetParam( Param => 'TakeLastSearch' ) || '';
    $Self->{SelectTemplate} = $Self->{ParamObject}->GetParam( Param => 'SelectTemplate' ) || '';
    $Self->{EraseTemplate}  = $Self->{ParamObject}->GetParam( Param => 'EraseTemplate' )  || '';
    my $Nav = $Self->{ParamObject}->GetParam( Param => 'Nav' ) || '';

    # search with a saved template
    if ( $Self->{ParamObject}->GetParam( Param => 'SearchTemplate' ) && $Self->{Profile} ) {
        return $Self->{LayoutObject}->Redirect(
            OP =>
                "Action=AgentFAQSearchSmall;Subaction=Search;TakeLastSearch=1;SaveProfile=1;Profile=$Self->{Profile};Nav=$Nav"
        );
    }

    # get single params
    my %GetParam;

    # load profiles string params (press load profile)
    if ( ( $Self->{Subaction} eq 'LoadProfile' && $Self->{Profile} ) || $Self->{TakeLastSearch} ) {
        %GetParam = $Self->{SearchProfileObject}->SearchProfileGet(
            Base      => 'FAQSearch',
            Name      => $Self->{Profile},
            UserLogin => $Self->{UserLogin},
        );
    }

    # get search string params (get submitted params)
    else {

        # get scalar search params
        for my $ParamName (
            qw(Number Title Keyword Fulltext ResultForm VoteSearch VoteSearchType VoteSearchOption
            RateSearch RateSearchType RateSearchOption ApprovedSearch
            TimeSearchType ChangeTimeSearchType
            ItemCreateTimePointFormat ItemCreateTimePoint
            ItemCreateTimePointStart
            ItemCreateTimeStart ItemCreateTimeStartDay ItemCreateTimeStartMonth
            ItemCreateTimeStartYear
            ItemCreateTimeStop ItemCreateTimeStopDay ItemCreateTimeStopMonth
            ItemCreateTimeStopYear
            ItemChangeTimePointFormat ItemChangeTimePoint
            ItemChangeTimePointStart
            ItemChangeTimeStart ItemChangeTimeStartDay ItemChangeTimeStartMonth
            ItemChangeTimeStartYear
            ItemChangeTimeStop ItemChangeTimeStopDay ItemChangeTimeStopMonth
            ItemChangeTimeStopYear
            )
            )
        {
            $GetParam{$ParamName} = $Self->{ParamObject}->GetParam( Param => $ParamName );

            # remove whitespace on the start and end
            if ( $GetParam{$ParamName} ) {
                $GetParam{$ParamName} =~ s{ \A \s+ }{}xms;
                $GetParam{$ParamName} =~ s{ \s+ \z }{}xms;
            }
        }

        # get array search params
        for my $SearchParam (
            qw(CategoryIDs LanguageIDs ValidIDs StateIDs CreatedUserIDs LastChangedUserIDs)
            )
        {
            my @Array = $Self->{ParamObject}->GetArray( Param => $SearchParam );
            if (@Array) {
                $GetParam{$SearchParam} = \@Array;
            }
        }
    }

    # get approved option
    if ( $GetParam{ApprovedSearch} && $GetParam{ApprovedSearch} eq 'Yes' ) {
        $GetParam{Approved} = 1;
    }
    elsif ( $GetParam{ApprovedSearch} && $GetParam{ApprovedSearch} eq 'No' ) {
        $GetParam{Approved} = 0;
    }

    # get vote option
    if ( !$GetParam{VoteSearchOption} ) {
        $GetParam{'VoteSearchOption::None'} = 'checked="checked"';
    }
    elsif ( $GetParam{VoteSearchOption} eq 'VotePoint' ) {
        $GetParam{'VoteSearchOption::VotePoint'} = 'checked="checked"';
    }

    # get rate option
    if ( !$GetParam{RateSearchOption} ) {
        $GetParam{'RateSearchOption::None'} = 'checked="checked"';
    }
    elsif ( $GetParam{RateSearchOption} eq 'RatePoint' ) {
        $GetParam{'RateSearchOption::RatePoint'} = 'checked="checked"';
    }

    # get create time option
    if ( !$GetParam{TimeSearchType} ) {
        $GetParam{'TimeSearchType::None'} = 'checked="checked"';
    }
    elsif ( $GetParam{TimeSearchType} eq 'TimePoint' ) {
        $GetParam{'TimeSearchType::TimePoint'} = 'checked="checked"';
    }
    elsif ( $GetParam{TimeSearchType} eq 'TimeSlot' ) {
        $GetParam{'TimeSearchType::TimeSlot'} = 'checked="checked"';
    }

    # get change time option
    if ( !$GetParam{ChangeTimeSearchType} ) {
        $GetParam{'ChangeTimeSearchType::None'} = 'checked="checked"';
    }
    elsif ( $GetParam{ChangeTimeSearchType} eq 'TimePoint' ) {
        $GetParam{'ChangeTimeSearchType::TimePoint'} = 'checked="checked"';
    }
    elsif ( $GetParam{ChangeTimeSearchType} eq 'TimeSlot' ) {
        $GetParam{'ChangeTimeSearchType::TimeSlot'} = 'checked="checked"';
    }

    # set result form env
    if ( !$GetParam{ResultForm} ) {
        $GetParam{ResultForm} = '';
    }

    # show result site
    if ( $Self->{Subaction} eq 'Search' && !$Self->{EraseTemplate} ) {

        # fill up profile name (e.g. with last-search)
        if ( !$Self->{Profile} || !$Self->{SaveProfile} ) {
            $Self->{Profile} = 'last-search';
        }

        # store last overview screen
        my $URL
            = "Action=AgentFAQSearchSmall;Subaction=Search;Profile=$Self->{Profile};SortBy=$Self->{SortBy}"
            . ";OrderBy=$Self->{OrderBy};TakeLastSearch=1;StartHit=$Self->{StartHit};Nav=$Nav";
        $Self->{SessionObject}->UpdateSessionID(
            SessionID => $Self->{SessionID},
            Key       => 'LastScreenOverview',
            Value     => $URL,
        );
        $Self->{SessionObject}->UpdateSessionID(
            SessionID => $Self->{SessionID},
            Key       => 'LastScreenView',
            Value     => $URL,
        );

        # save search profile (under last-search or real profile name)
        $Self->{SaveProfile} = 1;

        # remember last search values
        if ( $Self->{SaveProfile} && $Self->{Profile} ) {

            # remove old profile stuff
            $Self->{SearchProfileObject}->SearchProfileDelete(
                Base      => 'FAQSearch',
                Name      => $Self->{Profile},
                UserLogin => $Self->{UserLogin},
            );

            # insert new profile params
            for my $Key ( sort keys %GetParam ) {
                if ( $GetParam{$Key} ) {
                    $Self->{SearchProfileObject}->SearchProfileAdd(
                        Base      => 'FAQSearch',
                        Name      => $Self->{Profile},
                        Key       => $Key,
                        Value     => $GetParam{$Key},
                        UserLogin => $Self->{UserLogin},
                    );
                }
            }
        }

        # prepare votes search
        if ( IsNumber( $GetParam{VoteSearch} ) && $GetParam{VoteSearchOption} ) {
            $GetParam{Votes} = {
                $GetParam{VoteSearchType} => $GetParam{VoteSearch}
            };
        }

        # prepare rate search
        if ( IsNumber( $GetParam{RateSearch} ) && $GetParam{RateSearchOption} ) {
            $GetParam{Rate} = {
                $GetParam{RateSearchType} => $GetParam{RateSearch}
            };
        }

        my %TimeMap = (
            ItemCreate => 'Time',
            ItemChange => 'ChangeTime',
        );

        for my $TimeType ( sort keys %TimeMap ) {

            # get create time settings
            if ( !$GetParam{ $TimeMap{$TimeType} . 'SearchType' } ) {

                # do nothing with time stuff
            }
            elsif ( $GetParam{ $TimeMap{$TimeType} . 'SearchType' } eq 'TimeSlot' ) {
                for my $Key (qw(Month Day)) {
                    $GetParam{ $TimeType . 'TimeStart' . $Key }
                        = sprintf( "%02d", $GetParam{ $TimeType . 'TimeStart' . $Key } );
                    $GetParam{ $TimeType . 'TimeStop' . $Key }
                        = sprintf( "%02d", $GetParam{ $TimeType . 'TimeStop' . $Key } );
                }
                if (
                    $GetParam{ $TimeType . 'TimeStartDay' }
                    && $GetParam{ $TimeType . 'TimeStartMonth' }
                    && $GetParam{ $TimeType . 'TimeStartYear' }
                    )
                {
                    $GetParam{ $TimeType . 'TimeNewerDate' }
                        = $GetParam{ $TimeType . 'TimeStartYear' } . '-'
                        . $GetParam{ $TimeType . 'TimeStartMonth' } . '-'
                        . $GetParam{ $TimeType . 'TimeStartDay' }
                        . ' 00:00:00';
                }
                if (
                    $GetParam{ $TimeType . 'TimeStopDay' }
                    && $GetParam{ $TimeType . 'TimeStopMonth' }
                    && $GetParam{ $TimeType . 'TimeStopYear' }
                    )
                {
                    $GetParam{ $TimeType . 'TimeOlderDate' }
                        = $GetParam{ $TimeType . 'TimeStopYear' } . '-'
                        . $GetParam{ $TimeType . 'TimeStopMonth' } . '-'
                        . $GetParam{ $TimeType . 'TimeStopDay' }
                        . ' 23:59:59';
                }
            }
            elsif ( $GetParam{ $TimeMap{$TimeType} . 'SearchType' } eq 'TimePoint' ) {
                if (
                    $GetParam{ $TimeType . 'TimePoint' }
                    && $GetParam{ $TimeType . 'TimePointStart' }
                    && $GetParam{ $TimeType . 'TimePointFormat' }
                    )
                {
                    my $Time = 0;
                    if ( $GetParam{ $TimeType . 'TimePointFormat' } eq 'minute' ) {
                        $Time = $GetParam{ $TimeType . 'TimePoint' };
                    }
                    elsif ( $GetParam{ $TimeType . 'TimePointFormat' } eq 'hour' ) {
                        $Time = $GetParam{ $TimeType . 'TimePoint' } * 60;
                    }
                    elsif ( $GetParam{ $TimeType . 'TimePointFormat' } eq 'day' ) {
                        $Time = $GetParam{ $TimeType . 'TimePoint' } * 60 * 24;
                    }
                    elsif ( $GetParam{ $TimeType . 'TimePointFormat' } eq 'week' ) {
                        $Time = $GetParam{ $TimeType . 'TimePoint' } * 60 * 24 * 7;
                    }
                    elsif ( $GetParam{ $TimeType . 'TimePointFormat' } eq 'month' ) {
                        $Time = $GetParam{ $TimeType . 'TimePoint' } * 60 * 24 * 30;
                    }
                    elsif ( $GetParam{ $TimeType . 'TimePointFormat' } eq 'year' ) {
                        $Time = $GetParam{ $TimeType . 'TimePoint' } * 60 * 24 * 365;
                    }
                    if ( $GetParam{ $TimeType . 'TimePointStart' } eq 'Before' ) {

                        # more than ... ago
                        $GetParam{ $TimeType . 'TimeOlderMinutes' } = $Time;
                    }
                    elsif ( $GetParam{ $TimeType . 'TimePointStart' } eq 'Next' ) {

                        # within next
                        $GetParam{ $TimeType . 'TimeNewerMinutes' } = 0;
                        $GetParam{ $TimeType . 'TimeOlderMinutes' } = -$Time;
                    }
                    else {
                        # within last ...
                        $GetParam{ $TimeType . 'TimeOlderMinutes' } = 0;
                        $GetParam{ $TimeType . 'TimeNewerMinutes' } = $Time;
                    }
                }
            }
        }

        # prepare fulltext search
        if ( $GetParam{Fulltext} ) {
            $GetParam{ContentSearch} = 'OR';
            $GetParam{What}          = $GetParam{Fulltext};
        }

        # get valid list
        my %ValidList   = $Self->{ValidObject}->ValidList();
        my @AllValidIDs = keys %ValidList;

        # prepare search states
        my $SearchStates;
        if ( !IsArrayRefWithData( $GetParam{StateIDs} ) ) {
            $SearchStates = $Self->{InterfaceStates};
        }
        else {
            STATETYPEID:
            for my $StateTypeID ( @{ $GetParam{StateIDs} } ) {
                next STATETYPEID if !$StateTypeID;
                next STATETYPEID if !$Self->{InterfaceStates}->{$StateTypeID};
                $SearchStates->{$StateTypeID} = $Self->{InterfaceStates}->{$StateTypeID};
            }
        }

        # prepare votes search
        if ( IsNumber( $GetParam{VoteSearch} ) && $GetParam{VoteSearchOption} ) {
            $GetParam{Votes} = {
                $GetParam{VoteSearchType} => $GetParam{VoteSearch}
            };
        }

        # prepare rate search
        if ( IsNumber( $GetParam{RateSearch} ) && $GetParam{RateSearchOption} ) {
            $GetParam{Rate} = {
                $GetParam{RateSearchType} => $GetParam{RateSearch}
            };
        }

        # perform FAQ search
        # default search on all valid ids, this can be overwritten by %GetParam
        my @ViewableFAQIDs = $Self->{FAQObject}->FAQSearch(
            OrderBy             => [ $Self->{SortBy} ],
            OrderByDirection    => [ $Self->{OrderBy} ],
            Limit               => $Self->{SearchLimit},
            UserID              => $Self->{UserID},
            States              => $SearchStates,
            Interface           => $Self->{Interface},
            ContentSearchPrefix => '*',
            ContentSearchSuffix => '*',
            ValidIDs            => \@AllValidIDs,
            %GetParam,
        );

        # start html page
        my $Output = $Self->{LayoutObject}->Header( Type => 'Small' );
        $Self->{LayoutObject}->Print( Output => \$Output );
        $Output = '';

        $Self->{Filter} = $Self->{ParamObject}->GetParam( Param => 'Filter' ) || '';
        $Self->{View}   = $Self->{ParamObject}->GetParam( Param => 'View' )   || '';

        # show FAQ's
        my $LinkPage = 'Filter='
            . $Self->{LayoutObject}->LinkEncode( $Self->{Filter} )
            . ';View=' . $Self->{LayoutObject}->LinkEncode( $Self->{View} )
            . ';SortBy=' . $Self->{LayoutObject}->LinkEncode( $Self->{SortBy} )
            . ';OrderBy=' . $Self->{LayoutObject}->LinkEncode( $Self->{OrderBy} )
            . ';Profile=' . $Self->{Profile} . ';TakeLastSearch=1;Subaction=Search'
            . ';Nav=' . $Nav
            . ';';
        my $LinkSort = 'Filter='
            . $Self->{LayoutObject}->LinkEncode( $Self->{Filter} )
            . ';View=' . $Self->{LayoutObject}->LinkEncode( $Self->{View} )
            . ';Profile=' . $Self->{Profile} . ';TakeLastSearch=1;Subaction=Search'
            . ';Nav=' . $Nav

            . ';';
        my $LinkFilter = 'TakeLastSearch=1;Subaction=Search;Profile='
            . $Self->{LayoutObject}->LinkEncode( $Self->{Profile} )
            . ';Nav=' . $Nav
            . ';';
        my $LinkBack = 'Subaction=LoadProfile;Profile='
            . $Self->{LayoutObject}->LinkEncode( $Self->{Profile} )
            . ';Nav=' . $Nav
            . ';TakeLastSearch=1;';

        my $FilterLink
            = 'SortBy=' . $Self->{LayoutObject}->LinkEncode( $Self->{SortBy} )
            . ';OrderBy=' . $Self->{LayoutObject}->LinkEncode( $Self->{OrderBy} )
            . ';View=' . $Self->{LayoutObject}->LinkEncode( $Self->{View} )
            . ';Profile=' . $Self->{Profile} . ';TakeLastSearch=1;Subaction=Search'
            . ';Nav=' . $Nav
            . ';';

        # find out which columns should be shown
        my @ShowColumns;
        if ( $Self->{Config}->{ShowColumns} ) {

            # get all possible columns from config
            my %PossibleColumn = %{ $Self->{Config}->{ShowColumns} };

            # get the column names that should be shown
            COLUMNNAME:
            for my $Name ( sort keys %PossibleColumn ) {
                next COLUMNNAME if !$PossibleColumn{$Name};
                push @ShowColumns, $Name;
            }

            # enforce FAQ number column since is the link MasterAction hook
            if ( !$PossibleColumn{'Number'} ) {
                push @ShowColumns, 'Number';
            }
        }

        $Output .= $Self->{LayoutObject}->FAQListShow(
            FAQIDs => \@ViewableFAQIDs,
            Total  => scalar @ViewableFAQIDs,

            View => $Self->{View},

            Env        => $Self,
            LinkPage   => $LinkPage,
            LinkSort   => $LinkSort,
            LinkFilter => $LinkFilter,
            LinkBack   => $LinkBack,
            Profile    => $Self->{Profile},

            TitleName => 'Search Result',
            Limit     => $Self->{SearchLimit},

            Filter     => $Self->{Filter},
            FilterLink => $FilterLink,

            OrderBy => $Self->{OrderBy},
            SortBy  => $Self->{SortBy},

            ShowColumns => \@ShowColumns,
            Nav         => $Nav,
        );

        # build footer
        $Output .= $Self->{LayoutObject}->Footer( Type => 'Small' );
        return $Output;
    }

    else {
        $Output = $Self->{LayoutObject}->Header( Type => 'Small' );

        # create output
        $Output .= $Self->_MaskForm(
            Nav => $Nav,
            %GetParam,
        );
        $Output .= $Self->{LayoutObject}->Footer( Type => 'Small' );

        return $Output;
    }
}

sub _MaskForm {
    my ( $Self, %Param ) = @_;

    # get list type
    my $TreeView = 0;
    if ( $Self->{ConfigObject}->Get('Ticket::Frontend::ListType') eq 'tree' ) {
        $TreeView = 1;
    }

    # get profiles list
    my %Profiles = $Self->{SearchProfileObject}->SearchProfileList(
        Base      => 'FAQSearch',
        UserLogin => $Self->{UserLogin},
    );

    # build profiles output list
    $Param{ProfilesStrg} = $Self->{LayoutObject}->BuildSelection(
        Data         => {%Profiles},
        PossibleNone => 1,
        Name         => 'Profile',
        SelectedID   => $Param{Profile},
    );

    # get languages list
    my %Languages = $Self->{FAQObject}->LanguageList(
        UserID => $Self->{UserID},
    );

    # dropdown menu for 'languages'
    $Param{LanguagesSelectionStrg} = $Self->{LayoutObject}->BuildSelection(
        Data       => \%Languages,
        Name       => 'LanguageIDs',
        Size       => 5,
        Multiple   => 1,
        SelectedID => $Param{LanguageIDs} || [],
    );

    # get categories (with category long names) where user has rights
    my $UserCategoriesLongNames = $Self->{FAQObject}->GetUserCategoriesLongNames(
        Type   => 'rw',
        UserID => $Self->{UserID},
    );

    # build the category selection
    $Param{CategoriesSelectionStrg} = $Self->{LayoutObject}->BuildSelection(
        Data        => $UserCategoriesLongNames,
        Name        => 'CategoryIDs',
        SelectedID  => $Param{CategoryIDs} || [],
        Size        => 5,
        Translation => 0,
        Multiple    => 1,
        TreeView    => $TreeView,
    );

    # get valid list
    my %ValidList = $Self->{ValidObject}->ValidList();

    # build the valid selection
    $Param{ValidSelectionStrg} = $Self->{LayoutObject}->BuildSelection(
        Data        => \%ValidList,
        Name        => 'ValidIDs',
        SelectedID  => $Param{ValidIDs} || [],
        Size        => 5,
        Translation => 0,
        Multiple    => 1,
    );

    # create a mix of state and state types hash in order to have the state type IDs with state
    # names
    my %StateList = $Self->{FAQObject}->StateList(
        UserID => $Self->{UserID},
    );

    my %States;
    for my $StateID ( sort keys %StateList ) {
        my %StateData = $Self->{FAQObject}->StateGet(
            StateID => $StateID,
            UserID  => $Self->{UserID},
        );
        $States{ $StateData{TypeID} } = $StateData{Name}
    }

    $Param{StateSelectionStrg} = $Self->{LayoutObject}->BuildSelection(
        Data        => \%States,
        Name        => 'StateIDs',
        SelectedID  => $Param{StateIDs} || [],
        Size        => 3,
        Translation => 1,
        Multiple    => 1,
    );

    my %VotingOperators = (
        Equals            => 'Equals',
        GreaterThan       => 'GreaterThan',
        GreaterThanEquals => 'GreaterThanEquals',
        SmallerThan       => 'SmallerThan',
        SmallerThanEquals => 'SmallerThanEquals',
    );

    $Param{VoteSearchTypeSelectionStrg} = $Self->{LayoutObject}->BuildSelection(
        Data        => \%VotingOperators,
        Name        => 'VoteSearchType',
        SelectedID  => $Param{VoteSearchType} || '',
        Size        => 1,
        Translation => 1,
        Multiple    => 0,
    );

    $Param{RateSearchTypeSelectionStrg} = $Self->{LayoutObject}->BuildSelection(
        Data        => \%VotingOperators,
        Name        => 'RateSearchType',
        SelectedID  => $Param{RateSearchType} || '',
        Size        => 1,
        Translation => 1,
        Multiple    => 0,
    );
    $Param{RateSearchSelectionStrg} = $Self->{LayoutObject}->BuildSelection(
        Data => {
            0   => '0%',
            25  => '25%',
            50  => '50%',
            75  => '75%',
            100 => '100%',
        },
        Sort        => 'NumericKey',
        Name        => 'RateSearch',
        SelectedID  => $Param{RateSearch} || '',
        Size        => 1,
        Translation => 0,
        Multiple    => 0,
    );

    $Param{ApprovedStrg} = $Self->{LayoutObject}->BuildSelection(
        Data => {
            No  => 'No',
            Yes => 'Yes',
        },
        Name         => 'ApprovedSearch',
        SelectedID   => $Param{ApprovedSearch} || '',
        Multiple     => 0,
        Translation  => 1,
        PossibleNone => 1,
    );

    # get a list of all users to display
    my %ShownUsers = $Self->{UserObject}->UserList(
        Type  => 'Long',
        Valid => 1,
    );

    # get the UserIDs from faq and faq_admin members
    my %GroupUsers;
    for my $Group (qw(faq faq_admin)) {
        my $GroupID = $Self->{GroupObject}->GroupLookup( Group => $Group );
        my %Users = $Self->{GroupObject}->GroupMemberList(
            GroupID => $GroupID,
            Type    => 'rw',
            Result  => 'HASH',
        );
        %GroupUsers = ( %GroupUsers, %Users );
    }

    # remove all users that are not in the faq or faq_admin groups
    for my $UserID ( sort keys %ShownUsers ) {
        if ( !$GroupUsers{$UserID} ) {
            delete $ShownUsers{$UserID};
        }
    }
    $Param{CreatedUserStrg} = $Self->{LayoutObject}->BuildSelection(
        Data       => \%ShownUsers,
        Name       => 'CreatedUserIDs',
        Multiple   => 1,
        Size       => 5,
        SelectedID => $Param{CreatedUserIDs},
    );
    $Param{LastChangedUserStrg} = $Self->{LayoutObject}->BuildSelection(
        Data       => \%ShownUsers,
        Name       => 'LastChangedUserIDs',
        Multiple   => 1,
        Size       => 5,
        SelectedID => $Param{LastChangedUserIDs},
    );

    $Param{ItemCreateTimePointStrg} = $Self->{LayoutObject}->BuildSelection(
        Data       => [ 1 .. 59 ],
        Name       => 'ItemCreateTimePoint',
        SelectedID => $Param{ItemCreateTimePoint},
    );
    $Param{ItemCreateTimePointStartStrg} = $Self->{LayoutObject}->BuildSelection(
        Data => {
            'Last'   => 'within the last ...',
            'Before' => 'more than ... ago',
        },
        Name => 'ItemCreateTimePointStart',
        SelectedID => $Param{ItemCreateTimePointStart} || 'Last',
    );
    $Param{ItemCreateTimePointFormatStrg} = $Self->{LayoutObject}->BuildSelection(
        Data => {
            minute => 'minute(s)',
            hour   => 'hour(s)',
            day    => 'day(s)',
            week   => 'week(s)',
            month  => 'month(s)',
            year   => 'year(s)',
        },
        Name       => 'ItemCreateTimePointFormat',
        SelectedID => $Param{ItemCreateTimePointFormat},
    );
    $Param{ItemCreateTimeStartStrg} = $Self->{LayoutObject}->BuildDateSelection(
        %Param,
        Prefix   => 'ItemCreateTimeStart',
        Format   => 'DateInputFormat',
        DiffTime => -( ( 60 * 60 * 24 ) * 30 ),
    );
    $Param{ItemCreateTimeStopStrg} = $Self->{LayoutObject}->BuildDateSelection(
        %Param,
        Prefix => 'ItemCreateTimeStop',
        Format => 'DateInputFormat',
    );

    $Param{ItemChangeTimePointStrg} = $Self->{LayoutObject}->BuildSelection(
        Data       => [ 1 .. 59 ],
        Name       => 'ItemChangeTimePoint',
        SelectedID => $Param{ItemChangeTimePoint},
    );
    $Param{ItemChangeTimePointStartStrg} = $Self->{LayoutObject}->BuildSelection(
        Data => {
            'Last'   => 'within the last ...',
            'Before' => 'more than ... ago',
        },
        Name => 'ItemChangeTimePointStart',
        SelectedID => $Param{ItemChangeTimePointStart} || 'Last',
    );
    $Param{ItemChangeTimePointFormatStrg} = $Self->{LayoutObject}->BuildSelection(
        Data => {
            minute => 'minute(s)',
            hour   => 'hour(s)',
            day    => 'day(s)',
            week   => 'week(s)',
            month  => 'month(s)',
            year   => 'year(s)',
        },
        Name       => 'ItemChangeTimePointFormat',
        SelectedID => $Param{ItemChangeTimePointFormat},
    );
    $Param{ItemChangeTimeStartStrg} = $Self->{LayoutObject}->BuildDateSelection(
        %Param,
        Prefix   => 'ItemChangeTimeStart',
        Format   => 'DateInputFormat',
        DiffTime => -( ( 60 * 60 * 24 ) * 30 ),
    );
    $Param{ItemChangeTimeStopStrg} = $Self->{LayoutObject}->BuildDateSelection(
        %Param,
        Prefix => 'ItemChangeTimeStop',
        Format => 'DateInputFormat',
    );

    # html search mask output
    $Self->{LayoutObject}->Block(
        Name => 'Search',
        Data => {%Param},
    );

    # show languages select
    if ( $Self->{MultiLanguage} ) {
        $Self->{LayoutObject}->Block(
            Name => 'Language',
            Data => {%Param},
        );
    }

    # html search mask output
    return $Self->{LayoutObject}->Output(
        TemplateFile => 'AgentFAQSearchSmall',
        Data         => {%Param},
    );
}

1;
