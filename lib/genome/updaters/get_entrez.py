__author__ = 'Kelsy C Cotto'

import os
import gzip
import csv
import requests
from version_logger import Version
from bs4 import BeautifulSoup
import datetime


class Entrez:

    def __init__(self, download_path):
        self.online_version = None
        self.get_online_version()
        self.version = Version('Entrez', version=self.online_version, download_path=download_path)
        self.logged_version = self.version.last_logged_version()
        self.download_path = download_path
        # self.http = urllib3.PoolManager(cert_reqs='CERT_REQUIRED', ca_certs=certifi.where())

    def is_current(self):
        """Returns True if local versions of Entrez files are up-to-date."""
        return self.version.is_current()

    def get_online_version(self):
        # This assumes that if gene2accession needs updating, so will other Entrez files.
        r = requests.get('http://ftp.ncbi.nlm.nih.gov/gene/DATA/', stream=True, allow_redirects=True)
        bsObj = BeautifulSoup(r.text, "html.parser")
        for link in bsObj.find_all('a'):
            if link.get('href') == 'gene2accession.gz':
                self.online_version = datetime.datetime.strptime(link.next.next.split()[0], '%d-%b-%Y').strftime(
                    '%d-%B-%Y')
                break

    def download_file(self, url, local_filename):
        # NOTE the stream=True parameter
        r = requests.get(url, stream=True, allow_redirects=True, auth=HTTPBasicAuth(self.username, self.password))
        with open(local_filename, 'wb') as f:
            for chunk in r.iter_content(chunk_size=1024):
                if chunk:  # filter out keep-alive new chunks
                    f.write(chunk)

    def extract(self, file):
        with gzip.open(file, 'rb') as rf:
            with open(self.download_path + file.rsplit('.', 1)[0] + '.human', 'w') as wf:
                for i, line in enumerate(rf):
                    line_ascii = line.decode('utf-8')
                    if i == 0:
                        wf.write(line_ascii)
                    else:
                        species = line_ascii.split()[0]
                        if species == '9606':  # Grab human only
                            wf.write(line_ascii)

    def download_file(self, url, local_filename):
        # NOTE the stream=True parameter
        r = requests.get(url, stream=True, allow_redirects=True)
        with open(local_filename, 'wb') as f:
            for chunk in r.iter_content(chunk_size=1024):
                if chunk:  # filter out keep-alive new chunks
                    f.write(chunk)

    def download_files(self):
        """Download and extract the gene2accession and gene_info files"""
        print('Downloading Entrez Accessions...')
        print('gene2accession:')
        g2a_filename = 'gene2accession.gz'
        self.download_file("http://ftp.ncbi.nlm.nih.gov/gene/DATA/gene2accession.gz", g2a_filename)
        print('\ngene_info:')
        gi_filename = 'gene_info.gz'
        self.download_file("http://ftp.ncbi.nlm.nih.gov/gene/DATA/gene_info.gz", gi_filename)
        print('\ninteractions:')
        ia_filename = 'interactions.gz'
        self.download_file("http://ftp.ncbi.nlm.nih.gov/gene/GeneRIF/interactions.gz", ia_filename)
        print('\nExtracting Entrez Accessions...')
        print('gene_info...')
        self.extract("gene_info.gz")
        print('gene2accession...')
        self.extract("gene2accession.gz")
        print('interactions...')
        self.extract("interactions.gz")
        os.remove(g2a_filename)
        os.remove(gi_filename)
        os.remove(ia_filename)

    def parse(self):
        self.rows = []
        with open(self.download_path + 'gene_info.human') as f:
            fieldnames = ['tax_id', 'entrez_id', 'entrez_gene_symbol', 'locus_tag',
                         'entrez_gene_synonyms', 'dbXrefs', 'chromosome', 'map_loc',
                         'description', 'type', 'sym_from_auth', 'full_from_auth',
                         'nom_status', 'other_designations', 'mod_date']
            reader = csv.DictReader(f, delimiter='\t', fieldnames=fieldnames)
            for i, row in enumerate(reader):
                if i == 0:
                    continue
                ensembl = set()
                for key, value in row.items():
                    if value == '-':
                        row[key] = 'N/A'
                dbXrefs = row['dbXrefs'].split('|')
                for xRef in dbXrefs:
                    if xRef == 'N/A':
                        continue
                    source, label = xRef.split(':', 1)
                    if source == 'Ensembl':
                        ensembl.add(label)
                row['ensembl_ids'] = '|'.join(ensembl) or 'N/A'
                self.rows.append(row)

    def write(self):
        with open('entrez_genes.tsv', 'w') as f:
            fieldnames = ['entrez_id', 'entrez_gene_symbol', 'entrez_gene_synonyms',
                          'ensembl_ids', 'description']
            writer = csv.DictWriter(f, delimiter='\t', fieldnames=fieldnames, extrasaction='ignore')
            writer.writeheader()
            writer.writerows(self.rows)
        self.version.write_log()

    def update(self):
        if not self.is_current():
            self.download_files()
            self.parse()
            self.write()


if __name__ == '__main__':
    e = Entrez()
    e.update()
    print('Done.')
