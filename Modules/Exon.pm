package Exon;

=head1 DESCRIPTION

The package is used to obtain exon or genomic sequence, with or without indel.

=head1 SYNOPSIS

=head1 AUTHOR

Xuning Wang

=cut

use strict;
use Carp;
use Data::Dumper;

=head2 new

 Usage   : my $obj = new Exon('fasta_file'=>$fasta, 'seqid'=>$seqid);
 Function: Generate a new object
 Returns : a Exon object
 Args    : fasta_file, seqid, verbose, samtools
 	       Default samtools is the one in PATH environment.

=cut

sub new {
    my $self = shift;
    my %h    = (
        verbose => 1,
        @_,
    );
    required_args( \%h, 'fasta_file', 'seqid' );
    $h{samtools} //= 'samtools';
    return bless \%h, $self;
}

=head2 getSeq

 Usage   : my $seq=$obj->getSeq();
 Function: Return a string of sequence from fasta using samtools
	If fasta index file is not created before hand, it will be created in the same 
	directory as the fasta file. So make sure file/directory permission is granted.
	start and end are 1-based coordinates
 Returns : return a sequence string 
 Args    : start, end. Optional 

=cut

sub getSeq {
    my $self = shift;
    my %h    = (
        start => '',
        end   => '',
        @_
    );
    my $region = $self->{seqid};
    if ( $h{start} ) {
        $region .= ":$h{start}";
        if ( $h{end} ) {
            $region .= "-$h{end}";
        }
    }

    my $result = qx($self->{samtools} faidx $self->{fasta_file} $region) or 
      die "Could not create .fai file for $self->{fasta_file} likely due to permission\n";
    my @a = split( /\n/, $result );
    shift @a;
    return join( "", @a );
}

=head2 getExonsSeq

 
 Usage   : my ($seq, $aref)=$obj->getExonSeq(start=x, end=y, exonStarts=m1,m2, exonEnds=n1,n2) 
 Function: Obtain a sequence spliced from all exons within the range of start-end.
 Returns : Return a sequence and an reference of array of coordinates (0-based) of the bases in the sequence.
 Args    : start, end, exonStarts, and exonEnds. They are in UCSC refseq format: 0-based; end is exclusive.
	The coordinates are 1-based and inclusive. For insertion, sequence is inserted between the 2 positions.

=cut

sub getExonsSeq {
    my $self = shift;
    my %h    = ( @_, );

    required_args( \%h, 'start', 'end', 'exonStarts', 'exonEnds' );

    my @starts = split( /,/, $h{exonStarts} );
    my @ends   = split( /,/, $h{exonEnds} );

    # Obtain genomic sequence from start to end of all exons, on positive strand
    my $seq = $self->getSeq( start => $starts[0] + 1, end => $ends[-1] );

    my $exonseq = "";
    my @coords;    # 0-based
    my $offset = $starts[0];

    print STDERR "Exon#(positive_strand)\tStart(1-based)\tEnd(1-based)\n"
      if $self->{verbose};
    for ( my $i = 0 ; $i < @starts ; $i++ ) {
        $exonseq .=
          substr( $seq, $starts[$i] - $offset, $ends[$i] - $starts[$i] );
        print STDERR join( "\t", $i + 1, $starts[$i] + 1, $ends[$i] ) . "\n"
          if $self->{verbose};
        for ( my $j = $starts[$i] ; $j < $ends[$i] ; $j++ ) {
            push( @coords, $j );
        }
    }

    # set coord to -1 if it is outside the range of start-end
    for ( my $i = 0 ; $i < @coords ; $i++ ) {
        if ( $coords[$i] < $h{start} or $coords[$i] >= $h{end} ) {
            $coords[$i] = -1;
        }
    }

    # collect only the in-range bases and coordinates.
    my @bases = split( //, $exonseq );
    $exonseq = '';
    my @new_coords;
    for ( my $i = 0 ; $i < @coords ; $i++ ) {
        if ( $coords[$i] >= 0 ) {
            $exonseq .= $bases[$i];
            push( @new_coords, $coords[$i] );
        }
    }
    print STDERR "Exonseq:$exonseq\n" if $self->{verbose};
    return ( $exonseq, \@new_coords );
}

=head2 getMutantExonsSeq

 Usage   : my ($seq, $seg_aref, $intron_bases)= $obj->getMutantExonsSeq(wt_seq=, wt_coord=, indelstr= ) 
 Function: 
 Returns : Return a modified sequence due to indels, and segments to be used for canvas xpress
	The segments are like [1,15],[2],[16,30]: seq between 1 and 30, with insertion of 2 bases after 15.
	[1,15],[20,30]: seq between 1 and 30, with deletion of 16-19.
	Each pair of backets is called a segment, such as [1,15] or [2]. 
 Args    : wt_coords is array ref. Elements are 0-based coordinates. $indelstr is 1-based.
	indelstr is 1-based, e.g. 52272278:52272279:I:ATTTCA:52272290:52272291:D:.

=cut

sub getMutantExonsSeq {
    my $self = shift;
    my %h    = (@_);
    required_args( \%h, 'wt_seq', 'wt_coords', 'indelstr' );

    my @bases = split( //, $h{wt_seq} );
    my @coords = @{ $h{wt_coords} };
    my %hcoord;    # (coord=>base, ...)
    for ( my $i = 0 ; $i < @coords ; $i++ ) {
        $hcoord{ $coords[$i] } = $bases[$i];
    }

    my @ind = split( /:/, $h{indelstr} );
    my %inserted_seqs;    # {coord=>inserted seq}
    my ( $p, $q );        # 0-based, $p-inclusive, $q-not inclusive. [p,q)
    my $intron_bases = 0; # number of intronic bases in the indelstr
    for ( my $i = 0 ; $i < @ind ; $i += 4 ) {
        my $type = $ind[ $i + 2 ];
        $p = $ind[$i] - 1;
        if ( $type eq "I" ) {
            if ( $hcoord{$p} ) {
                ## store the inserted sequence in a new hash
                $inserted_seqs{$p} = $ind[ $i + 3 ];
            }
            else {
                $intron_bases += length( $ind[ $i + 3 ] );
            }
        }
        elsif ( $type eq "D" ) {
            ## Mark off the affected positions from the wt
            $q = $ind[ $i + 1 ] - 1;
            print STDERR "Processing indelstr $ind[$i] ...\n"
              if $self->{verbose};
            for ( my $j = $p ; $j <= $q ; $j++ ) {
                if ( $hcoord{$j} ) {
                    print STDERR
"DELETION: Base $hcoord{$j} at coord index $j in exon is deleted.\n"
                      if $self->{verbose};
                    $hcoord{$j} = '';
                }
                else {
                    print STDERR
                      "DELETION: Base at coord index $j in intron is deleted.\n"
                      if $self->{verbose};
                    $intron_bases++;
                }
            }
        }
    }

    if ( $self->{verbose} ) {
        print STDERR "Inserted seqs: " . Dumper(%inserted_seqs) . "\n"
          if %inserted_seqs;
    }

    # Now connect the available bases and obtain segments
    my $door = 'closed';
    my $newseq;
    my @segments;    # ([n1,n2], [n3], [n4, n5])
    my ( $start, $end );

    for ( my $i = 0 ; $i < @coords ; $i++ ) {
        my $c        = $coords[$i];
        my $cur_base = $hcoord{$c};

        if ($cur_base) {

            # a real base
            $newseq .= $cur_base;

            if ( $door eq 'closed' ) {
                $start = $i + 1;
                $door  = 'open';
                print STDERR "Started a segment at index $i.\n"
                  if $self->{verbose};
            }

            # If there is insertion
            if ( $inserted_seqs{$c} ) {
                $newseq .= $inserted_seqs{$c};

                # close current segment
                $end = $i + 1;
                push( @segments, "[$start,$end]" );
                $door = 'closed';

                # start a segment for inserted seq
                my $len = length( $inserted_seqs{$c} );
                push( @segments, "[$len]" );
            }

            if ( $i == $#coords && $door eq 'open' ) {

                # last real base. Close segment
                $end = $i + 1;
                push( @segments, "[$start,$end]" );
                $door = 'closed';
                print STDERR "Closed the last segment at index $i.\n"
                  if $self->{verbose};
            }

        }
        else {

            # start of a deleted base
            if ( $door eq 'open' ) {

                # close the segment
                $end = $i;
                push( @segments, "[$start,$end]" );
                $door = 'closed';

                print STDERR
                  "Encountered deletion. So closed a segment at index $i.\n"
                  if $self->{verbose};
            }
        }
    }

    print "In CDS + strand, segments: @segments\n" if $self->{verbose};
    return ( $newseq, \@segments, $intron_bases );
}

=head2 locateGuideInCDS

 Usage   : my ($segment_str, $guide_cds_seq, $intron_bases) = $obj->locateGuideInCDS(args)
 Function: Find the location of guide sequence in CDS.
 Returns : Return the guide sequence and its location inside CD
	Guide sequence is a short stretch (usually 20 bases) of sequence, and can be in exon/intron.
 Args    : guide_start and guide_end are genomic coordinates and are 1-based inclusive.
	strand is the direction of the gene.

=cut

sub locateGuideInCDS {
    my $self = shift;
    my %h = ( strand => '+', @_ );

    required_args( \%h, 'strand', 'cdsStart', 'cdsEnd', 'exonStarts',
        'exonEnds', 'guide_start', 'guide_end' );

    my ( $cds_chr_seq, $cds_chr_coords ) = $self->getExonsSeq(
        start      => $h{cdsStart},
        end        => $h{cdsEnd},
        exonStarts => $h{exonStarts},
        exonEnds   => $h{exonEnds}
    );
    my @bases = split( //, $cds_chr_seq );
    my @coords = @$cds_chr_coords;    # 0-based
    ## @coords contains coordinates of each CDS base.
    my $cds_len = scalar(@coords);
    print STDERR "CDS exon sequence length: $cds_len\n" if $self->{verbose};

    my %hash;    # cds coord=>base
    for ( my $i = 0 ; $i < @coords ; $i++ ) {
        $hash{ $coords[$i] } = $bases[$i];
    }

    # locate sgRNA
    my $guide_cds_seq;
    my ( $guide_start_in_cds, $guide_end_in_cds );
    my $intron_bases = 0;
    for ( my $i = $h{guide_start} - 1 ; $i < $h{guide_end} ; $i++ ) {
        if ( !$hash{$i} ) {
            print STDERR "Guide position(1-based) "
              . ( $i + 1 )
              . " is not in CDS.\n";
            $intron_bases++;
            next;
        }

        if ( !$guide_start_in_cds ) {
            $guide_start_in_cds = $i + 1;
        }
        $guide_cds_seq .= $hash{$i};
        $guide_end_in_cds = $i + 1;
    }

    my @segments;
    if ($guide_start_in_cds) {

        # Guide has base(s) in CDS. Only the segment in CDS will be returned

        ## offsetted start and end, with cds start being 1
        my ( $guide_start_loc, $guide_end_loc );
        for ( my $i = 0 ; $i < @coords ; $i++ ) {
            if ( $coords[$i] == $guide_start_in_cds - 1 ) {
                $guide_start_loc = $i + 1;
                $guide_end_loc   = $guide_start_loc +
                  ( $guide_end_in_cds - $guide_start_in_cds );
                push( @segments, "[$guide_start_loc,$guide_end_loc]" );
                last;
            }
        }

    }
    else {

        # Guide is completely inside intron. Find the nearest exon coordinate.
        print STDERR "Guide is completely inside intron\n";
        my $guide_len = $h{guide_end} - $h{guide_start} + 1;

        my $guide_start_idx = $h{guide_start} - 1;
        if ( $guide_start_idx < $coords[0] ) {
            push( @segments, "[-1,-1]" );
        }
        elsif ( $guide_start_idx > $coords[-1] ) {
            push( @segments,
                "[" . ( $cds_len + 1 ) . "," . ( $cds_len + 1 ) . "]" );
        }
        else {
            for ( my $i = 0 ; $i < @coords - 1 ; $i++ ) {
                if (   $guide_start_idx > $coords[$i]
                    && $guide_start_idx < $coords[ $i + 1 ] )
                {
                    push( @segments,
                        "[" . ( $i + 1 ) . "," . ( $i + 1 ) . "]" );
                    print STDERR "Guide is between CDS bases #$i and # "
                      . ( $i + 1 ) . "\n";
                    last;
                }
            }
        }
    }

    if ( $self->{verbose} ) {
        print STDERR "In CDS + strand, guide seq: $guide_cds_seq\n";
        print STDERR "In CDS + strand, guide segments: @segments\n";
    }

    if ( $h{strand} eq '-' ) {
        $guide_cds_seq = $self->revcom($guide_cds_seq) if $guide_cds_seq;
        my $aref = $self->reverse_segments(
            segment_aref => \@segments,
            total_length => $cds_len
        );
        @segments = @$aref;
        if ( $self->{verbose} ) {
            print STDERR "In CDS - strand, guide seq: $guide_cds_seq\n";
            print STDERR "In CDS - strand, guide segments: @segments\n";
        }
    }

    return ( join( ",", @segments ), $guide_cds_seq, $intron_bases );
}

=head2 reverse_segments

 Usage   : my $seg_aref = $obj->reverse_segments($old_seg_aref)
 Function: Change the direction of the segments, i.e. change original start to end, original end to start, .. 
 Returns : Return a reference of the segement array
 Args    : total_length, by default, is the length of the segment in wildtype 

=cut

sub reverse_segments {
    my $self = shift;
    my %h = ( total_length => '', @_ );
    required_args( \%h, 'segment_aref' );

    my @tmp = @{ $h{segment_aref} };
    my $total;
    if ( !$h{total_length} ) {
        my ( $min, $max );
        foreach my $s (@tmp) {
            if ( $s =~ /(\d+),(\d+)/ ) {
                $min = $1 if !$min;
                $max = $2 if ( !$max or $max < $2 );
            }
        }

        $total = $min + $max;
    }
    else {
        $total = 1 + $h{total_length};
    }

    my @segments;
    for ( my $i = $#tmp ; $i >= 0 ; $i-- ) {
        if ( $tmp[$i] =~ /(\d+),(\d+)/ ) {
            my $start = $total - $2;
            my $end   = $total - $1;
            push( @segments, "[$start,$end]" );
        }
        elsif ( $tmp[$i] =~ /\d+/ ) {
            push( @segments, $tmp[$i] );
        }
    }
    return \@segments;
}

=head2 getGenomicSeq

 Function: Obtain a modified sequence after indel.  
 Returns : genomic sequence, and segment array reference 
 Args    : indelstr is like 123:145:D::155:156:I:ATCG
	start_pos is where the 1st base in the input_seq starts in a coordinate system used by indelstr
	Both start_pos and indel str use 1-based coordinate.
	The input_seq, start_pos and indelstr are all based on a positive strand direction
	The input_seq is a contigous sequence, like genomic sequence.
	strand can be + or -. 

=cut

sub getGenomicSeq {
    my $self = shift;
    my %h = ( strand => '+', @_ );
    required_args( \%h, 'input_seq', 'start_pos', 'indelstr' );
    my ( $seq, $segment_aref ) =
      $self->getGenomicSeq_PositiveStrand( $h{input_seq}, $h{start_pos},
        $h{indelstr} );
    if ( $h{strand} eq '-' ) {
        $seq = $self->revcom($seq);
        $segment_aref =
          $self->reverse_segments( segment_aref => $segment_aref );
    }

    return ( $seq, $segment_aref );
}

sub getGenomicSeq_PositiveStrand {
    my $self = shift;
    my %h    = (@_);
    required_args( \%h, 'input_seq', 'start_pos', 'indelstr' );

    my @bases = split( //,  $h{input_seq} );
    my @ind   = split( /:/, $h{indelstr} );

    ## Add bases to or cancel bases from the input seq
    for ( my $i = 0 ; $i < @ind ; $i += 4 ) {
        if ( $ind[ $i + 2 ] eq "I" ) {
            $bases[ $ind[$i] - $h{start_pos} ] .= $ind[ $i + 3 ];
        }
        elsif ( $ind[ $i + 2 ] eq "D" ) {
            for ( my $j = $ind[$i] ; $j <= $ind[ $i + 1 ] ; $j++ ) {
                $bases[ $j - $h{start_pos} ] = "";
            }
        }
    }

    my @segments;    # segmentation of sequence.
     # [1,15],[2],[16,30]: seq between 1 and 30, with insertion of 2 bases after 15.
     # [1,15],[20,30]: seq between 1 and 30, with deletion of 16-19.
    my ( $start, $len );
    for ( my $i = 1 ; $i <= @bases ; $i++ ) {
        $len = length( $bases[ $i - 1 ] );
        if ( $len == 1 && !$start ) {
            $start = $i;
        }

        ## When encountering insertion, deletion or sequence end, close the segment
        if ( $len != 1 or $i == @bases ) {
            if ($start) {
                my $end = $len == 0 ? $i - 1 : $i;
                push( @segments, "[$start,$end]" );
                $start = 0;
            }
        }

        ## Added a segment for inserted sequence.
        if ( $len > 1 ) {
            push( @segments, "[" . ( $len - 1 ) . "]" );
        }
    }

    return ( join( "", @bases ), \@segments );
}

sub revcom {
    my ( $self, $seq ) = @_;
    my $rc = reverse($seq);
    $rc =~ tr/ACGTacgt/TGCAtgca/;
    return $rc;
}

sub required_args {
    my $href = shift;
    foreach my $arg (@_) {
        if ( !defined $href->{$arg} ) {
            croak "Missing required argument: $arg";
        }
    }
}

1;
